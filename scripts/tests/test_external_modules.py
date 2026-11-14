"""Exercise locked module setup with local Git remotes, without network access."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "setup-external-modules.py"


def git(path, *args):
    return subprocess.check_output(
        ["git", "-C", str(path), *args], text=True, stderr=subprocess.DEVNULL
    ).strip()


class ExternalModulesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.root = base / "checkout"
        (self.root / ".github/ci-patches").mkdir(parents=True)
        self.patch = self.root / ".github/ci-patches/bakasu.patch"
        self.lock = {"schema_version": 1, "modules": {}}
        self.counts = {}
        for name, directory in [
            ("kernelsu", "KernelSU"), ("nomount", "NoMount"),
            ("baseband_guard", "Baseband-guard"),
        ]:
            repo = base / directory
            repo.mkdir()
            git(repo, "init", "--quiet")
            git(repo, "config", "user.name", "Module setup test")
            git(repo, "config", "user.email", "test@example.invalid")
            source = repo / "source.c"
            source.write_text("original\n")
            git(repo, "add", "source.c")
            git(repo, "commit", "--quiet", "-m", "base")
            commit = git(repo, "rev-parse", "HEAD")
            if name == "kernelsu":
                source.write_text("local integration\n")
                git(repo, "commit", "--quiet", "-am", "integration")
                patch = git(repo, "diff", "--binary", commit, "HEAD") + "\n"
                self.patch.write_text(patch)
            elif name == "nomount":
                source.write_text("second upstream commit\n")
                git(repo, "commit", "--quiet", "-am", "update")
                commit = git(repo, "rev-parse", "HEAD")
            spec = {
                "repository": str(repo), "commit": commit,
                "tree": git(repo, "rev-parse", "HEAD^{tree}"),
            }
            if name == "kernelsu":
                spec.update(patch=".github/ci-patches/bakasu.patch",
                            patch_sha256=hashlib.sha256(self.patch.read_bytes()).hexdigest())
            self.lock["modules"][name] = spec
            self.counts[name] = git(repo, "rev-list", "--count", commit)

    def run_setup(self):
        (self.root / ".github/external-modules.json").write_text(json.dumps(self.lock))
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root)],
            capture_output=True, text=True,
        )

    def assert_nothing_installed(self):
        for name in ("KernelSU", "NoMount", "Baseband-guard"):
            self.assertFalse((self.root / name).exists())

    def test_reconstructs_patch_preserves_history_and_links(self):
        # Git checkout can leave an empty placeholder for an uninitialized submodule.
        (self.root / "KernelSU").mkdir()
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "KernelSU/source.c").read_text(), "local integration\n")
        self.assertEqual(git(self.root / "NoMount", "rev-list", "--count", "HEAD"),
                         self.counts["nomount"])
        self.assertEqual(os.readlink(self.root / "fs/nomount"), "../NoMount/kernel/src")
        self.assertEqual(git(self.root / "KernelSU", "write-tree"),
                         self.lock["modules"]["kernelsu"]["tree"])

    def test_refuses_existing_checkout_without_touching_it(self):
        destination = self.root / "NoMount"
        destination.mkdir()
        sentinel = destination / "local-work"
        sentinel.write_text("keep me")
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to replace existing checkout", result.stderr)
        self.assertEqual(sentinel.read_text(), "keep me")
        self.assertFalse((self.root / "KernelSU").exists())

    def test_rejects_patch_checksum_change(self):
        self.patch.write_text("tampered patch\n")
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("patch checksum", result.stderr)
        self.assert_nothing_installed()

    def test_rejects_patch_that_does_not_apply(self):
        self.patch.write_text("not a patch\n")
        self.lock["modules"]["kernelsu"]["patch_sha256"] = hashlib.sha256(
            self.patch.read_bytes()).hexdigest()
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assert_nothing_installed()

    def test_last_module_tree_mismatch_installs_nothing(self):
        self.lock["modules"]["baseband_guard"]["tree"] = "0" * 40
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source tree does not match", result.stderr)
        self.assert_nothing_installed()

    def test_rejects_unpinned_reference(self):
        self.lock["modules"]["nomount"]["commit"] = "dev"
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("full Git object ID", result.stderr)
        self.assert_nothing_installed()

    def test_refuses_unexpected_symlink(self):
        (self.root / "fs").mkdir()
        (self.root / "fs/nomount").symlink_to("../my-local-work")
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected symlink", result.stderr)
        self.assertEqual(os.readlink(self.root / "fs/nomount"), "../my-local-work")
        self.assert_nothing_installed()


if __name__ == "__main__":
    unittest.main()
