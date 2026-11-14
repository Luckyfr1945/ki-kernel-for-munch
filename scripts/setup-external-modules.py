#!/usr/bin/env python3
"""Reconstruct CI dependencies from public commits and checked-in patches."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


MODULES = {
    "kernelsu": ("KernelSU", "drivers/kernelsu", "../KernelSU/kernel"),
    "nomount": ("NoMount", "fs/nomount", "../NoMount/kernel/src"),
    "baseband_guard": ("Baseband-guard", "security/baseband-guard", "../Baseband-guard"),
}


def git(directory, *args):
    result = subprocess.run(
        ["git", "-C", str(directory), *args],
        check=True, text=True, stdout=subprocess.PIPE,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )
    return result.stdout.strip()


def prepare(root, lockfile):
    lock = json.loads(lockfile.read_text())
    if lock.get("schema_version") != 1 or set(lock.get("modules", {})) != set(MODULES):
        raise ValueError("Unsupported or incomplete external module lockfile")

    patches = {}
    for name, (directory, link, target) in MODULES.items():
        spec = lock["modules"][name]
        for field in ("commit", "tree"):
            if not re.fullmatch(r"[0-9a-f]{40}", spec.get(field, "")):
                raise ValueError(f"{name}: {field} must be a full Git object ID")
        if not spec.get("repository"):
            raise ValueError(f"{name}: repository is required")
        destination = root / directory
        if destination.is_symlink() or (
            destination.exists() and (
                not destination.is_dir() or any(destination.iterdir())
            )
        ):
            raise ValueError(f"Refusing to replace existing checkout: {destination}")
        linkpath = root / link
        if linkpath.is_symlink():
            if os.readlink(linkpath) != target:
                raise ValueError(f"Refusing to replace unexpected symlink: {linkpath}")
        elif linkpath.exists():
            raise ValueError(f"Refusing to replace existing path: {linkpath}")

        if spec.get("patch"):
            patch = (root / spec["patch"]).resolve()
            if not patch.is_relative_to(root):
                raise ValueError(f"{name}: patch must be inside the source checkout")
            digest = hashlib.sha256(patch.read_bytes()).hexdigest()
            if digest != spec.get("patch_sha256"):
                raise ValueError(f"{name}: patch checksum does not match lockfile")
            patches[name] = patch

    # Download and verify all modules before installing any of them.
    with tempfile.TemporaryDirectory(prefix=".external-modules-", dir=root) as staging:
        for name, (directory, _, _) in MODULES.items():
            spec = lock["modules"][name]
            checkout = Path(staging) / directory
            checkout.mkdir()
            git(checkout, "init", "--quiet")
            git(checkout, "remote", "add", "origin", spec["repository"])
            # Keep ancestry: Kbuild derives version codes from commit counts.
            git(checkout, "fetch", "--quiet", "--no-tags", "--filter=blob:none",
                "origin", spec["commit"])
            git(checkout, "-c", "submodule.recurse=false", "checkout", "--quiet",
                "--detach", "FETCH_HEAD")
            if git(checkout, "rev-parse", "HEAD") != spec["commit"]:
                raise ValueError(f"{name}: fetched commit does not match lockfile")
            if name in patches:
                git(checkout, "apply", "--check", str(patches[name]))
                git(checkout, "apply", str(patches[name]))
            git(checkout, "add", "-A")
            if git(checkout, "write-tree") != spec["tree"]:
                raise ValueError(f"{name}: source tree does not match lockfile")
            print(f"Verified {name}: {spec['commit']}", flush=True)

        for directory, link, target in MODULES.values():
            destination = root / directory
            if destination.exists():
                destination.rmdir()  # Only empty checkout placeholders are allowed.
            (Path(staging) / directory).rename(destination)
            linkpath = root / link
            linkpath.parent.mkdir(parents=True, exist_ok=True)
            if not linkpath.is_symlink():
                linkpath.symlink_to(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        prepare(root, root / ".github/external-modules.json")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"External module setup failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
