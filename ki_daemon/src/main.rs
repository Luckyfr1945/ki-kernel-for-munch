use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, exit};
use std::thread::sleep;
use std::time::{Duration, Instant};

const CONF_SDCARD: &str = "/sdcard/ki_daemon.conf";
const CONF_MODULE: &str = "/data/adb/modules/ki_optimizer/ki_daemon.conf";
const PID_FILE: &str = "/data/adb/modules/ki_optimizer/daemon.pid";
const STATUS_FILE: &str = "/data/adb/modules/ki_optimizer/daemon.status";

const DEFAULT_GAMES: &[&str] = &[
    "com.mobile.legends",
    "com.miHoYo.GenshinImpact",
    "com.nexon.bluearchive",
    "com.YoStar.AetherGazer",
    "com.YoStarEN.Arknights",
    "com.YoStarEN.AzurLane",
    "com.hypergryph.arknights",
    "com.kurogame.haru.google",
    "com.HoYoverse.nap",
    "com.miHoYo.nap",
    "com.dts.freefireth",
    "com.tencent.ig",
    "com.activision.callofduty.shooter",
    "com.garena.game.codm",
    "com.riotgames.league.wildrift",
    "com.pubg.imobile",
    "com.epicgames.fortnite",
    "com.proximabeta.mf.uamo",
    "com.levelinfinite.hotta.gp",
    "com.kurogame.wutheringwaves.global",
    "com.HoYoverse.hkrpgoversea",
    "com.miHoYo.Yuanshen",
    "com.garena.game.kgid",
    "org.citra.citra_emu",
    "org.yuzu.yuzu_emu",
    "skyline.emu",
    "org.dolphinemu.dolphinemu",
    "xyz.aethersx2.android",
    "com.retroarch.aarch64",
];

const IGNORED_PACKAGES: &[&str] = &[
    "system_server",
    "surfaceflinger",
    "zygote",
    "zygote64",
    "webview_zygote",
    "com.android.systemui",
    "com.android.launcher",
    "com.android.launcher3",
    "com.miui.home",
    "com.mi.android.globallauncher",
    "com.google.android.apps.nexuslauncher",
    "com.google.android.inputmethod.latin",
    "com.touchtype.swiftkey",
    "com.google.android.gms",
    "com.android.settings",
    "android.process.media",
    "android.process.acore",
];

#[derive(Clone, Debug)]
pub struct DaemonConfig {
    pub enabled: bool,
    pub poll_interval_ms: u64,
    pub default_profile: u32,
    pub game_profile: u32,
    pub auto_bypass_charging: bool,
    pub auto_mglru: bool,
    pub game_mglru: u32,
    pub default_mglru: u32,
    pub games: HashSet<String>,
}

impl Default for DaemonConfig {
    fn default() -> Self {
        let mut games = HashSet::new();
        for g in DEFAULT_GAMES {
            games.insert((*g).to_string());
        }
        Self {
            enabled: true,
            poll_interval_ms: 1500,
            default_profile: 1, // Balanced
            game_profile: 2,    // Turbo Gaming
            auto_bypass_charging: true,
            auto_mglru: true,
            game_mglru: 1,      // 0x0001 Standard (Core LRU - no page table walk lockup)
            default_mglru: 1,   // 0x0001 Standard
            games,
        }
    }
}

impl DaemonConfig {
    pub fn get_conf_path() -> &'static str {
        if Path::new(CONF_SDCARD).exists() {
            CONF_SDCARD
        } else if Path::new(CONF_MODULE).exists() {
            CONF_MODULE
        } else {
            CONF_SDCARD
        }
    }

    pub fn load() -> Self {
        let mut cfg = DaemonConfig::default();
        let path = Self::get_conf_path();

        if let Ok(file) = File::open(path) {
            let reader = BufReader::new(file);
            for line in reader.lines().flatten() {
                let trimmed = line.trim();
                if trimmed.is_empty() || trimmed.starts_with('#') {
                    continue;
                }
                if let Some((key, val)) = trimmed.split_once('=') {
                    let k = key.trim();
                    let v = val.trim().trim_matches('"');
                    match k {
                        "DAEMON_ENABLED" => cfg.enabled = v == "1" || v.eq_ignore_ascii_case("true"),
                        "POLL_INTERVAL_MS" => {
                            if let Ok(n) = v.parse::<u64>() {
                                cfg.poll_interval_ms = n.max(500);
                            }
                        }
                        "DEFAULT_PROFILE" => {
                            if let Ok(n) = v.parse::<u32>() {
                                cfg.default_profile = n;
                            }
                        }
                        "GAME_PROFILE" => {
                            if let Ok(n) = v.parse::<u32>() {
                                cfg.game_profile = n;
                            }
                        }
                        "AUTO_BYPASS_CHARGING" => {
                            cfg.auto_bypass_charging = v == "1" || v.eq_ignore_ascii_case("true")
                        }
                        "AUTO_MGLRU" => cfg.auto_mglru = v == "1" || v.eq_ignore_ascii_case("true"),
                        "GAME_MGLRU" => {
                            if let Ok(n) = v.parse::<u32>() {
                                cfg.game_mglru = n;
                            }
                        }
                        "DEFAULT_MGLRU" => {
                            if let Ok(n) = v.parse::<u32>() {
                                cfg.default_mglru = n;
                            }
                        }
                        "GAMES" => {
                            cfg.games.clear();
                            for item in v.split(',') {
                                let pkg = item.trim();
                                if !pkg.is_empty() {
                                    cfg.games.insert(pkg.to_string());
                                }
                            }
                        }
                        _ => {}
                    }
                }
            }
        } else {
            cfg.save();
        }

        cfg
    }

    pub fn save(&self) {
        let path = Self::get_conf_path();
        let mut games_vec: Vec<_> = self.games.iter().cloned().collect();
        games_vec.sort();
        let games_str = games_vec.join(",");

        let content = format!(
            "# Ki-Daemon Auto Game Turbo Configuration\n\
             # Location: {path}\n\
             DAEMON_ENABLED={}\n\
             POLL_INTERVAL_MS={}\n\
             DEFAULT_PROFILE={}\n\
             GAME_PROFILE={}\n\
             AUTO_BYPASS_CHARGING={}\n\
             AUTO_MGLRU={}\n\
             GAME_MGLRU={}\n\
             DEFAULT_MGLRU={}\n\
             GAMES=\"{}\"\n",
            if self.enabled { 1 } else { 0 },
            self.poll_interval_ms,
            self.default_profile,
            self.game_profile,
            if self.auto_bypass_charging { 1 } else { 0 },
            if self.auto_mglru { 1 } else { 0 },
            self.game_mglru,
            self.default_mglru,
            games_str
        );

        let _ = fs::write(path, content);
        let _ = Command::new("chmod").args(["666", path]).status();
    }
}

// Low-overhead sysfs / procfs helpers
fn write_node(path: &str, val: &str) -> bool {
    fs::write(path, val).is_ok()
}

fn read_node_trimmed(path: &str) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

fn is_charger_connected() -> bool {
    if let Some(status) = read_node_trimmed("/sys/class/power_supply/battery/status") {
        if status.eq_ignore_ascii_case("Charging") || status.eq_ignore_ascii_case("Full") {
            return true;
        }
    }
    if let Some(online) = read_node_trimmed("/sys/class/power_supply/usb/online") {
        if online == "1" {
            return true;
        }
    }
    false
}

fn set_kernel_profile(mode: u32) {
    let mode_str = mode.to_string();
    if !write_node("/proc/ki_profile", &mode_str) {
        write_node("/sys/kernel/ki_profile/mode", &mode_str);
    }
}

fn set_bypass_charging(enabled: bool) {
    let val = if enabled { "1" } else { "0" };
    if !write_node("/proc/bypass_charging", val) {
        write_node("/sys/class/power_supply/battery/bypass_charging", val);
    }
}

fn set_mglru(mode: u32) {
    let val = mode.to_string();
    if !write_node("/proc/mglru", &val) {
        write_node("/sys/kernel/mm/lru_gen/enabled", &val);
    }
}

fn is_screen_on() -> bool {
    // 1. Direct in-kernel display notifier state
    if let Some(val) = read_node_trimmed("/sys/kernel/ki_profile/screen_state") {
        return val == "1";
    }
    // 2. Hardware panel backlight brightness
    if let Some(val) = read_node_trimmed("/sys/class/backlight/panel0-backlight/brightness") {
        if let Ok(b) = val.parse::<u32>() {
            return b > 0;
        }
    }
    // 3. Fallback: DRM runtime status
    if let Some(val) = read_node_trimmed("/sys/class/drm/card0/device/power/runtime_status") {
        if val == "active" {
            return true;
        }
    }
    true
}

// Strategy 1: Ultra-fast top-app cgroup reading (0 fork overhead, in-memory)
fn get_foreground_app_cgroup(cfg: &DaemonConfig) -> Option<(String, bool)> {
    let cgroup_paths = [
        "/dev/cpuset/top-app/cgroup.procs",
        "/dev/cpuset/top-app/tasks",
        "/sys/fs/cgroup/cpuset/top-app/cgroup.procs",
    ];

    let mut candidate_app: Option<String> = None;

    for cpath in &cgroup_paths {
        if let Ok(content) = fs::read_to_string(cpath) {
            let pids: Vec<&str> = content.lines().collect();

            for pid_str in pids {
                let pid = pid_str.trim();
                if pid.is_empty() {
                    continue;
                }
                let cmd_path = format!("/proc/{pid}/cmdline");
                if let Ok(cmd_bytes) = fs::read(&cmd_path) {
                    if cmd_bytes.is_empty() {
                        continue;
                    }
                    // Extract first null-terminated string
                    let end = cmd_bytes.iter().position(|&b| b == 0).unwrap_or(cmd_bytes.len());
                    let raw_pkg = String::from_utf8_lossy(&cmd_bytes[..end]).trim().to_string();

                    if raw_pkg.is_empty() || raw_pkg.starts_with('/') {
                        continue;
                    }

                    // Strip process suffix: e.g. "com.mobile.legends:UnityKillsMe" -> "com.mobile.legends"
                    let base_pkg = raw_pkg.split(':').next().unwrap_or(&raw_pkg).trim();

                    // Android apps must have a dot '.' and not be a CLI tool like 'ping' or 'sh'
                    if base_pkg.contains('.') && base_pkg.len() >= 4 {
                        // Check if it's directly in our configured game library
                        if cfg.games.contains(base_pkg) {
                            return Some((base_pkg.to_string(), true));
                        }

                        if !IGNORED_PACKAGES.iter().any(|&ig| base_pkg == ig || base_pkg.starts_with(ig)) {
                            if candidate_app.is_none() {
                                candidate_app = Some(base_pkg.to_string());
                            }
                        }
                    }
                }
            }
        }
    }

    candidate_app.map(|app| {
        let is_game = cfg.games.contains(&app);
        (app, is_game)
    })
}

// Strategy 2: Fallback via dumpsys window / activity (only if Strategy 1 yields nothing)
fn get_foreground_app_dumpsys(cfg: &DaemonConfig) -> Option<(String, bool)> {
    let output = Command::new("dumpsys")
        .args(["window", "displays"])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&output.stdout);

    for line in text.lines() {
        if line.contains("mCurrentFocus") || line.contains("mFocusedApp") {
            // example: mCurrentFocus=Window{... u0 com.mobile.legends/com.xxx.MainActivity}
            if let Some(start) = line.find(" u0 ") {
                let sub = &line[start + 4..];
                let pkg_part = sub.split(&['/', ' ', '}', ':'][..]).next().unwrap_or("");
                let clean = pkg_part.trim();
                if clean.contains('.') && clean.len() >= 4 && !IGNORED_PACKAGES.iter().any(|&ig| clean == ig) {
                    let is_game = cfg.games.contains(clean);
                    return Some((clean.to_string(), is_game));
                }
            }
        }
    }
    None
}

fn get_foreground_app(cfg: &DaemonConfig) -> (String, bool) {
    if let Some((pkg, is_game)) = get_foreground_app_cgroup(cfg) {
        if is_game {
            return (pkg, true);
        }
        // If cgroup found a generic app, check dumpsys in case top-app had background helper
        if let Some((dumpsys_pkg, true)) = get_foreground_app_dumpsys(cfg) {
            return (dumpsys_pkg, true);
        }
        return (pkg, false);
    }
    if let Some((pkg, is_game)) = get_foreground_app_dumpsys(cfg) {
        return (pkg, is_game);
    }
    ("com.android.launcher".to_string(), false)
}

fn write_status(
    running: bool,
    fg_pkg: &str,
    is_game: bool,
    active_profile: u32,
    bypass_active: bool,
    cfg: &DaemonConfig,
) {
    let content = format!(
        "RUNNING={}\n\
         PID={}\n\
         FOREGROUND_PKG={}\n\
         IS_GAME={}\n\
         ACTIVE_PROFILE={}\n\
         BYPASS_CHARGING={}\n\
         DAEMON_ENABLED={}\n\
         AUTO_BYPASS={}\n\
         AUTO_MGLRU={}\n\
         GAMES_COUNT={}\n",
        if running { 1 } else { 0 },
        std::process::id(),
        fg_pkg,
        if is_game { 1 } else { 0 },
        active_profile,
        if bypass_active { 1 } else { 0 },
        if cfg.enabled { 1 } else { 0 },
        if cfg.auto_bypass_charging { 1 } else { 0 },
        if cfg.auto_mglru { 1 } else { 0 },
        cfg.games.len()
    );

    let _ = fs::write(STATUS_FILE, content);
}

fn run_daemon() {
    let pid = std::process::id();
    let _ = fs::write(PID_FILE, pid.to_string());

    println!("[Ki-Daemon] Started successfully with PID: {pid}");

    let mut cfg = DaemonConfig::load();
    let mut last_cfg_check = Instant::now();
    let mut is_game_active = false;
    let mut bypass_engaged_by_daemon = false;
    let mut current_profile = cfg.default_profile;
    let mut last_pkg = String::new();

    loop {
        // Reload config every 3 seconds
        if last_cfg_check.elapsed() >= Duration::from_secs(3) {
            cfg = DaemonConfig::load();
            last_cfg_check = Instant::now();
        }

        if !cfg.enabled {
            if is_game_active {
                // Restore defaults before sleeping
                set_kernel_profile(cfg.default_profile);
                if bypass_engaged_by_daemon {
                    set_bypass_charging(false);
                    bypass_engaged_by_daemon = false;
                }
                if cfg.auto_mglru {
                    set_mglru(cfg.default_mglru);
                }
                is_game_active = false;
            }
            write_status(true, "disabled", false, cfg.default_profile, false, &cfg);
            sleep(Duration::from_secs(4));
            continue;
        }

        // If screen is off, sleep longer to preserve battery in pocket
        if !is_screen_on() {
            write_status(true, "screen_off", is_game_active, current_profile, bypass_engaged_by_daemon, &cfg);
            sleep(Duration::from_secs(4));
            continue;
        }

        let (fg_pkg, is_game) = get_foreground_app(&cfg);

        if is_game && !is_game_active {
            // ENTER GAME MODE
            println!("[Ki-Daemon] Game detected: {fg_pkg} -> Engaging Game Turbo!");
            set_kernel_profile(cfg.game_profile);
            current_profile = cfg.game_profile;

            if cfg.auto_bypass_charging && is_charger_connected() {
                set_bypass_charging(true);
                bypass_engaged_by_daemon = true;
                println!("[Ki-Daemon] Charger connected -> Auto Bypass Charging engaged!");
            }

            if cfg.auto_mglru {
                set_mglru(cfg.game_mglru);
                println!("[Ki-Daemon] Auto MGLRU set to Gaming Turbo ({})", cfg.game_mglru);
            }

            is_game_active = true;
        } else if is_game && is_game_active {
            if current_profile != cfg.game_profile {
                set_kernel_profile(cfg.game_profile);
                current_profile = cfg.game_profile;
                println!("[Ki-Daemon] Game profile synchronized to {}", cfg.game_profile);
            }
            if cfg.auto_mglru {
                set_mglru(cfg.game_mglru);
            }
            // STILL IN GAME: monitor charger plug/unplug for bypass charging
            if cfg.auto_bypass_charging {
                let plugged = is_charger_connected();
                if plugged && !bypass_engaged_by_daemon {
                    set_bypass_charging(true);
                    bypass_engaged_by_daemon = true;
                } else if !plugged && bypass_engaged_by_daemon {
                    set_bypass_charging(false);
                    bypass_engaged_by_daemon = false;
                }
            }
        } else if !is_game && is_game_active {
            // EXIT GAME MODE -> RESTORE BALANCED
            println!("[Ki-Daemon] Game exited: {last_pkg} -> Restoring Default Profile ({})", cfg.default_profile);
            set_kernel_profile(cfg.default_profile);
            current_profile = cfg.default_profile;

            if bypass_engaged_by_daemon {
                set_bypass_charging(false);
                bypass_engaged_by_daemon = false;
                println!("[Ki-Daemon] Bypass Charging disarmed.");
            }

            if cfg.auto_mglru {
                set_mglru(cfg.default_mglru);
            }

            is_game_active = false;
        }

        last_pkg = fg_pkg.clone();
        write_status(
            true,
            &fg_pkg,
            is_game_active,
            current_profile,
            bypass_engaged_by_daemon,
            &cfg,
        );

        sleep(Duration::from_millis(cfg.poll_interval_ms));
    }
}

fn print_status() {
    let is_running = if let Ok(pid_str) = fs::read_to_string(PID_FILE) {
        let pid = pid_str.trim();
        Path::new(&format!("/proc/{pid}")).exists()
    } else {
        false
    };

    if !is_running {
        println!("{{\"running\": false}}");
        return;
    }

    if let Ok(content) = fs::read_to_string(STATUS_FILE) {
        let mut map = std::collections::HashMap::new();
        for line in content.lines() {
            if let Some((k, v)) = line.split_once('=') {
                map.insert(k.trim(), v.trim());
            }
        }

        let cfg = DaemonConfig::load();
        let mut games_vec: Vec<_> = cfg.games.iter().cloned().collect();
        games_vec.sort();

        print!("{{\n");
        print!("  \"running\": true,\n");
        print!("  \"pid\": {},\n", map.get("PID").unwrap_or(&"0"));
        print!("  \"foreground_pkg\": \"{}\",\n", map.get("FOREGROUND_PKG").unwrap_or(&"unknown"));
        print!("  \"is_game\": {},\n", map.get("IS_GAME").unwrap_or(&"0") == &"1");
        print!("  \"active_profile\": {},\n", map.get("ACTIVE_PROFILE").unwrap_or(&"1"));
        print!("  \"bypass_charging\": {},\n", map.get("BYPASS_CHARGING").unwrap_or(&"0") == &"1");
        print!("  \"daemon_enabled\": {},\n", cfg.enabled);
        print!("  \"default_profile\": {},\n", cfg.default_profile);
        print!("  \"game_profile\": {},\n", cfg.game_profile);
        print!("  \"auto_bypass\": {},\n", cfg.auto_bypass_charging);
        print!("  \"auto_mglru\": {},\n", cfg.auto_mglru);
        print!("  \"games\": {:?}\n", games_vec);
        print!("}}\n");
    } else {
        println!("{{\"running\": true, \"status\": \"initializing\"}}");
    }
}

fn stop_daemon() {
    if let Ok(pid_str) = fs::read_to_string(PID_FILE) {
        let pid = pid_str.trim();
        let _ = Command::new("kill").arg(pid).status();
        let _ = fs::remove_file(PID_FILE);
        let _ = fs::remove_file(STATUS_FILE);
        println!("Ki-Daemon stopped.");
    } else {
        let _ = Command::new("killall").arg("ki_daemon").status();
        println!("Ki-Daemon stop signal sent.");
    }
}

fn add_game(pkg: &str) {
    let mut cfg = DaemonConfig::load();
    if !pkg.trim().is_empty() {
        cfg.games.insert(pkg.trim().to_string());
        cfg.save();
        println!("Added game: {pkg}");
    }
}

fn remove_game(pkg: &str) {
    let mut cfg = DaemonConfig::load();
    if cfg.games.remove(pkg.trim()) {
        cfg.save();
        println!("Removed game: {pkg}");
    } else {
        println!("Game not found in list: {pkg}");
    }
}

fn set_config_value(key: &str, val: &str) {
    let mut cfg = DaemonConfig::load();
    match key.to_uppercase().as_str() {
        "DAEMON_ENABLED" => cfg.enabled = val == "1" || val.eq_ignore_ascii_case("true"),
        "POLL_INTERVAL_MS" => {
            if let Ok(n) = val.parse() {
                cfg.poll_interval_ms = n;
            }
        }
        "DEFAULT_PROFILE" => {
            if let Ok(n) = val.parse() {
                cfg.default_profile = n;
            }
        }
        "GAME_PROFILE" => {
            if let Ok(n) = val.parse() {
                cfg.game_profile = n;
            }
        }
        "AUTO_BYPASS" | "AUTO_BYPASS_CHARGING" => {
            cfg.auto_bypass_charging = val == "1" || val.eq_ignore_ascii_case("true")
        }
        "AUTO_MGLRU" => cfg.auto_mglru = val == "1" || val.eq_ignore_ascii_case("true"),
        "GAME_MGLRU" => {
            if let Ok(n) = val.parse() {
                cfg.game_mglru = n;
            }
        }
        "DEFAULT_MGLRU" => {
            if let Ok(n) = val.parse() {
                cfg.default_mglru = n;
            }
        }
        _ => {
            eprintln!("Unknown config key: {key}");
            return;
        }
    }
    cfg.save();
    println!("Updated {key} = {val}");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        println!("Ki-Daemon v1.0 (Auto Game Turbo & Optimization)");
        println!("Usage: ki_daemon <run|status|stop|add-game|remove-game|set>");
        return;
    }

    match args[1].as_str() {
        "run" => run_daemon(),
        "status" => print_status(),
        "stop" => stop_daemon(),
        "add-game" => {
            if args.len() >= 3 {
                add_game(&args[2]);
            } else {
                eprintln!("Usage: ki_daemon add-game <package_name>");
            }
        }
        "remove-game" => {
            if args.len() >= 3 {
                remove_game(&args[2]);
            } else {
                eprintln!("Usage: ki_daemon remove-game <package_name>");
            }
        }
        "set" => {
            if args.len() >= 4 {
                set_config_value(&args[2], &args[3]);
            } else {
                eprintln!("Usage: ki_daemon set <key> <val>");
            }
        }
        _ => {
            eprintln!("Unknown command: {}", args[1]);
            exit(1);
        }
    }
}
