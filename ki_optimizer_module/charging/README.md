# Charging limit monitor

Small, dependency-free Rust monitor for the Ki-Kernel munch charging driver.
Default: off. The WebUI toggle applies immediately and persists across reboot.
It enables kernel bypass at 80% and resumes at 75%, checking every 30 seconds.
An idle Unix socket allows immediate stop without polling a shell or spawning
commands. The monitor does not hold a wake lock: checks can be delayed during
system suspend, so 80% is a target rather than an exact hardware cutoff.

The monitor writes only bypass_charging and tracks ownership in the
root-only /data/adb/ki-charge-limit directory. Manual bypass takes priority. Existing
night charging or a battery pause owned by another controller prevents startup.
Do not run another charging limit controller at the same time. The driver's battery_input_suspend vote proved unstable on the device; the
dedicated bypass voter also disables the charge pump and survives ROM resets. Disabling the feature releases only the pause recorded as its own.
Read/write errors stop the monitor and attempt to release its pause. If the
process is forcibly killed, run off to release it, or on to resume monitoring.
Disabling/removing the module is checked on each interval; uninstall also calls off.

Commands (root):

```sh
/data/adb/modules/ki_optimizer/bin/ki-charge-limit on
/data/adb/modules/ki_optimizer/bin/ki-charge-limit off
/data/adb/modules/ki_optimizer/bin/ki-charge-limit status
```

Build and test:

```sh
rustup target add aarch64-unknown-linux-musl
cargo test --manifest-path charging/Cargo.toml
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=rust-lld cargo build --manifest-path charging/Cargo.toml --release --target aarch64-unknown-linux-musl
cp charging/target/aarch64-unknown-linux-musl/release/ki-charge-limit bin/ki-charge-limit
```

Device validation includes ARM64 fixture tests for thresholds, driver writes,
ownership, bypass, conflicting controllers, singleton locking and socket stop.
Real charging cutoff/resume still needs a charging cycle with bypass turned off.
