# Locked external modules

CI reads `.github/external-modules.json` instead of following moving branches.
This update preserves the source versions used by the local kernel:

| Module | Public commit | Local integration |
| --- | --- | --- |
| BakaSU | `548d1dda060ca198823d8808804d01f5209ef4a9` | `.github/ci-patches/bakasu.patch` reconstructs the tracked source tree of local commit `042cd11f6996ab2859aac1695a35bcdf902fde4f`. |
| NoMount | `ab93ee32a589ccb021257b3c1f280e058520d844` | v2.3.0-720, no local content changes. |
| Baseband-guard | `a54e0dc6cf0aff4dd87fec49644a02d2eb612905` | No local content changes; local executable-bit differences are not imported. |

Every entry records the expected Git tree. BakaSU's patch also has a SHA-256
checksum. Missing commits, checksum mismatches, failed patches and unexpected
source trees stop setup. There is no branch fallback or ignored patch failure.

## Fresh CI/source checkout

Use a fresh, nonrecursive source checkout, then run:

```sh
python3 scripts/setup-external-modules.py
```

The existing KernelSU gitlink records a customized local commit; CI deliberately
does not initialize it from upstream. Instead it fetches the public base and
applies the checked-in patch. This preserves source contents without requiring
those local commits to exist on BakaSU's public remote.

The helper requires absent or empty module directories and the expected symlinks.
It refuses to overwrite existing checkouts or unexpected paths. All three modules
are downloaded and verified in a temporary directory before installation.
Existing local KernelSU, NoMount and Baseband-guard checkouts are left intact by
this maintenance task.

Fetches retain commit ancestry because module Kbuild files derive version codes
from commit counts. The lock guarantees source trees, not identical timestamps,
toolchains, Git tag metadata or version strings between a customized local Git
history and CI's base-plus-patch checkout.

## Updating a pin

1. Review the chosen upstream commit and local compatibility patches.
2. Test the patch against that exact commit in a separate checkout.
3. Update its full commit ID, resulting tree ID and patch checksum in the lock.
4. Run setup in a fresh directory and build the affected kernel variants.

Do not regenerate the lock from a moving branch automatically during CI.

## Validation

```sh
python3 -m unittest discover -s scripts/tests -p test_external_modules.py -v
```

Tests use local Git remotes and cover patch reconstruction, ancestry, empty
submodule placeholders, refusal to overwrite local work, invalid patch hashes,
patch failures, unexpected trees, unpinned references and unexpected symlinks.
The workflow runs these checks before downloading real module sources.

A clean-room fetch of all three public commits also passed: BakaSU's resulting
tree is `c7f59cbba81604cdb29e72190a83a1e6fc2e35ba`, identical to the customized
local checkout. NoMount and Baseband-guard match their recorded trees as well.
The existing BakaSU patch reports whitespace warnings during application; its
contents were preserved and its resulting tree was verified. No new Image/ZIP
was built or CI run dispatched by this maintenance task.
