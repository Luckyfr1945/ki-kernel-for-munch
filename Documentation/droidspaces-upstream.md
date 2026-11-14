# Droidspaces upstream support on this 4.19 tree

Reference: [ravindu644/Droidspaces-OSS at cdadb9eb5d0f86aacffff60776333e6f6b73a30a](https://github.com/ravindu644/Droidspaces-OSS/tree/cdadb9eb5d0f86aacffff60776333e6f6b73a30a).
Requirements are taken from Documentation/Kernel-Configuration.md, non-GKI
configuration and firewall sections. This updates kernel support only; the
Droidspaces Android application and userspace runtime are not vendored here.

## Configuration changes

- Enable DEVTMPFS and NF_TABLES directly in munch_defconfig. Previously these
  were enabled by build.sh only; a direct defconfig build omitted them.
- Use NF_CT_NETLINK, the actual conntrack netlink symbol in this tree, instead
  of the nonexistent NF_CONNTRACK_NETLINK spelling in build.sh.
- Explicitly request SYSCTL and IP6_NF_TARGET_REJECT in the build helper.
- Remove nonexistent config names from the helper and munch's container block.
- Check 79 supported upstream options after olddefconfig, before compilation,
  on both build.sh paths (AOSP and MIUI/ColorOS). Missing options fail the build
  instead of silently disappearing when dependencies are resolved.

The helper's existing extra networking, USB gadget and loop-device options are
preserved. KernelSU and OS-specific build adjustments remain in place.

## Kernel-version differences

| Upstream guide spelling | This tree |
| --- | --- |
| NF_CONNTRACK_NETLINK | NF_CT_NETLINK |
| NF_CONNTRACK_IPV4 / NF_CONNTRACK_IPV6 | No separate Kconfig switches; conntrack is unified under NF_CONNTRACK. |
| NETFILTER_XT_TARGET_MASQUERADE | Use IP_NF_TARGET_MASQUERADE and IP6_NF_TARGET_MASQUERADE. |
| IP_NF_TARGET_ULOG | Not available; retain NETFILTER_NETLINK_LOG and NETFILTER_XT_TARGET_NFLOG. |
| ANDROID_PARANOID_NETWORK | No such Kconfig symbol in this tree. |
| FW_LOADER_COMPRESS | Not implemented in this 4.19 firmware loader; not added as a fake config switch. |

FW_LOADER and FW_LOADER_USER_HELPER remain enabled. Compressed firmware loading
has not been backported. The config checker therefore validates the supported
4.19 requirements, not every literal symbol in the upstream guide. It does not
guarantee all optional hardware/container workloads will work.

## Upstream non-GKI patches

- 5011f9b440c8c4144473d9a26171fc8ecf59d059, xt_qtaguid panic workaround:
  not applicable. net/netfilter/xt_qtaguid.c is absent from this kernel.
- 50cb2ccbef7d84852f2600bb4d3e69f6bd736561, cgroup prefix aliases:
  equivalent code already exists in cgroup_add_file() in kernel/cgroup/cgroup.c.
  No duplicate patch applied.

GKI ABI-padding patches are not applicable to this non-GKI 4.19 kernel.

## Validation

Run against resolved Kconfig output, not against a minimal defconfig:

```sh
bash scripts/check-droidspaces-config.sh out/.config
```

Validation during this update uses a separate /tmp/ki-droidspaces-config output
directory so the existing out/ build and its Image are not replaced. After
building and flashing, run the Droidspaces app's Requirements check and a real
container test to validate userspace, SELinux and networking on the chosen ROM.

Checks completed for this update:

- Fresh munch_defconfig: all 79 supported options pass.
- Build helper followed by olddefconfig: pass.
- AOSP and MIUI/ColorOS OS-specific settings followed by olddefconfig: pass.
- Existing out/.config: pass.
- Negative check with DEVTMPFS disabled: correctly exits with an error.
- bash -n and git diff --check: pass.

No new Image/ZIP was compiled or flashed, and no Droidspaces container was
started as part of this configuration update.
