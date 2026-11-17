use std::{
    env,
    fs::{self, File},
    io::{self, Read, Write},
    os::{
        fd::AsRawFd,
        unix::{
            fs::PermissionsExt,
            net::{UnixListener, UnixStream},
        },
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::Duration,
};

const STATE: &str = "/data/adb/ki-charge-limit";
const BATTERY: &str = "/sys/class/power_supply/battery";
#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}
unsafe extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
    fn poll(fds: *mut PollFd, count: usize, timeout: i32) -> i32;
    fn geteuid() -> u32;
}
fn err(message: &str) -> io::Error {
    io::Error::other(message)
}
fn read(path: impl AsRef<Path>) -> io::Result<String> {
    Ok(fs::read_to_string(path)?.trim().into())
}
fn put(path: impl AsRef<Path>, value: &str) -> io::Result<()> {
    fs::write(path, value)
}
fn remove(path: impl AsRef<Path>) -> io::Result<()> {
    match fs::remove_file(path) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        result => result,
    }
}
fn request(state: &Path, command: &str) -> io::Result<String> {
    let mut stream = UnixStream::connect(state.join("control"))?;
    stream.set_read_timeout(Some(Duration::from_secs(3)))?;
    stream.set_write_timeout(Some(Duration::from_secs(3)))?;
    stream.write_all(command.as_bytes())?;
    let mut response = String::new();
    stream.read_to_string(&mut response)?;
    Ok(response)
}
struct Controller {
    state: PathBuf,
    battery: PathBuf,
}
impl Controller {
    fn node(&self, name: &str) -> PathBuf {
        self.battery.join(name)
    }
    fn release(&self) -> io::Result<()> {
        if self.state.join("held-bypass").exists() {
            put(self.node("bypass_charging"), "0")?;
            remove(self.state.join("held-bypass"))?;
        }
        Ok(())
    }
    fn tick(&self) -> io::Result<&'static str> {
        let held = self.state.join("held-bypass").exists();
        let bypass = read(self.node("bypass_charging"))?;
        if bypass != "0" && bypass != "1" {
            return Err(err("Invalid bypass state"));
        }
        if bypass == "1" && !held {
            return Ok("Waiting for manual bypass to turn off");
        }
        let capacity: u8 = read(self.node("capacity"))?
            .parse()
            .map_err(|_| err("Invalid battery capacity"))?;
        if capacity > 100 {
            return Err(err("Invalid battery capacity"));
        }
        if !held {
            if read(self.node("battery_input_suspend"))? != "0" {
                return Err(err("Charging is paused by another controller"));
            }
            if read(self.node("night_charging"))? != "0" {
                return Err(err("Night charging is active"));
            }
        }
        if decision(capacity, held) {
            put(self.state.join("held-bypass"), "1")?;
            if bypass != "1" {
                put(self.node("bypass_charging"), "1")?;
            }
            if read(self.node("bypass_charging"))? != "1" {
                return Err(err("Driver did not enable bypass"));
            }
            Ok("Bypass active · limit 80%")
        } else {
            self.release()?;
            Ok("Monitoring · 80% / 75%")
        }
    }
}
fn decision(capacity: u8, held: bool) -> bool {
    capacity >= 80 || (held && capacity > 75)
}
fn run(controller: &Controller) -> io::Result<()> {
    let state = &controller.state;
    let lock = File::options()
        .create(true)
        .truncate(false)
        .write(true)
        .open(state.join("lock"))?;
    if unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 {
        return Err(err("Monitor already running"));
    }
    if !state.join("enabled").exists() {
        return Ok(());
    }
    remove(state.join("control"))?;
    let socket = UnixListener::bind(state.join("control"))?;
    fs::set_permissions(state.join("control"), fs::Permissions::from_mode(0o600))?;
    let result = (|| -> io::Result<()> {
        loop {
            if !state.join("enabled").exists()
                || Path::new("/data/adb/modules/ki_optimizer/disable").exists()
                || Path::new("/data/adb/modules/ki_optimizer/remove").exists()
            {
                remove(state.join("enabled"))?;
                break;
            }
            let status = controller.tick()?;
            put(state.join("status"), status)?;
            let mut fd = PollFd {
                fd: socket.as_raw_fd(),
                events: 1,
                revents: 0,
            };
            // Polling the control socket sleeps until a command arrives or 30 seconds pass.
            let ready = unsafe { poll(&mut fd, 1, 30_000) };
            if ready < 0 {
                return Err(io::Error::last_os_error());
            }
            if ready > 0 {
                let (mut client, _) = socket.accept()?;
                client.set_read_timeout(Some(Duration::from_secs(1)))?;
                client.set_write_timeout(Some(Duration::from_secs(1)))?;
                let mut buf = [0; 16];
                let count = client.read(&mut buf).unwrap_or(0);
                if &buf[..count] == b"stop" {
                    remove(state.join("enabled"))?;
                    controller.release()?;
                    let _ = client.write_all(b"Off");
                    break;
                }
                let _ = client.write_all(status.as_bytes());
            }
        }
        Ok(())
    })();
    let cleanup = controller.release();
    let _ = remove(state.join("control"));
    if let Err(ref error) = result {
        let _ = put(state.join("status"), &format!("Error: {error}"));
        let _ = remove(state.join("enabled"));
    }
    result.and(cleanup)
}
fn main() {
    if let Err(error) = main_result() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
fn main_result() -> io::Result<()> {
    if unsafe { geteuid() } != 0 {
        return Err(err("Root required"));
    }
    let state = PathBuf::from(STATE);
    fs::create_dir_all(&state)?;
    fs::set_permissions(&state, fs::Permissions::from_mode(0o700))?;
    let controller = Controller {
        state: state.clone(),
        battery: PathBuf::from(BATTERY),
    };
    match env::args().nth(1).as_deref() {
        Some("run") => run(&controller),
        Some("on") => {
            if request(&state, "status").is_ok() {
                return Ok(());
            }
            put(state.join("enabled"), "1")?;
            if let Err(error) = Command::new(env::current_exe()?)
                .arg("run")
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
            {
                remove(state.join("enabled"))?;
                return Err(error);
            }
            for _ in 0..30 {
                thread::sleep(Duration::from_millis(100));
                if let Ok(status) = request(&state, "status") {
                    println!("{status}");
                    return Ok(());
                }
                if !state.join("enabled").exists()
                    || Path::new("/data/adb/modules/ki_optimizer/disable").exists()
                    || Path::new("/data/adb/modules/ki_optimizer/remove").exists()
                {
                    remove(state.join("enabled"))?;
                    break;
                }
            }
            remove(state.join("enabled"))?;
            Err(err(
                &read(state.join("status")).unwrap_or_else(|_| "Monitor failed to start".into())
            ))
        }
        Some("off") => {
            match request(&state, "stop") {
                Ok(_) => (),
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::NotFound | io::ErrorKind::ConnectionRefused
                    ) =>
                {
                    remove(state.join("enabled"))?;
                    controller.release()?
                }
                Err(error) => return Err(error),
            }
            put(state.join("status"), "Off")?;
            println!("Off");
            Ok(())
        }
        Some("status") => {
            let live = request(&state, "status");
            let enabled = state.join("enabled").exists() && live.is_ok();
            let status = live.unwrap_or_else(|_| {
                if state.join("enabled").exists() || state.join("held-bypass").exists() {
                    "Monitor stopped; toggle on to restart or off to release".into()
                } else {
                    read(state.join("status")).unwrap_or_else(|_| "Off".into())
                }
            });
            println!(
                "ENABLED={}\nAUTO_BYPASS={}\nSTATUS={status}",
                if enabled { 1 } else { 0 },
                if state.join("held-bypass").exists() {
                    1
                } else {
                    0
                }
            );
            Ok(())
        }
        _ => Err(err("Usage: ki-charge-limit on|off|status|run")),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn thresholds() {
        assert!(decision(80, false));
        assert!(decision(100, false));
        assert!(!decision(79, false));
        assert!(decision(76, true));
        assert!(!decision(75, true));
        assert!(!decision(0, true));
    }
    #[test]
    fn driver_and_ownership() {
        let root = env::temp_dir().join(format!("ki-charge-test-{}", std::process::id()));
        fs::create_dir_all(root.join("state")).unwrap();
        fs::create_dir_all(root.join("battery")).unwrap();
        let c = Controller {
            state: root.join("state"),
            battery: root.join("battery"),
        };
        for (name, value) in [
            ("bypass_charging", "0"),
            ("night_charging", "0"),
            ("battery_input_suspend", "0"),
            ("capacity", "80"),
        ] {
            put(c.node(name), value).unwrap();
        }
        c.tick().unwrap();
        assert_eq!(read(c.node("bypass_charging")).unwrap(), "1");
        c.tick().unwrap();
        assert!(c.state.join("held-bypass").exists());
        put(c.node("capacity"), "76").unwrap();
        c.tick().unwrap();
        assert_eq!(read(c.node("bypass_charging")).unwrap(), "1");
        put(c.node("capacity"), "75").unwrap();
        c.tick().unwrap();
        assert_eq!(read(c.node("bypass_charging")).unwrap(), "0");
        put(c.node("bypass_charging"), "1").unwrap();
        c.tick().unwrap();
        c.release().unwrap();
        assert_eq!(read(c.node("bypass_charging")).unwrap(), "1");
        put(c.node("bypass_charging"), "0").unwrap();
        put(c.node("battery_input_suspend"), "1").unwrap();
        assert!(c.tick().is_err());
        put(c.node("battery_input_suspend"), "0").unwrap();
        put(c.node("night_charging"), "1").unwrap();
        assert!(c.tick().is_err());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn socket_start_status_stop() {
        let root = env::temp_dir().join(format!("ki-charge-socket-{}", std::process::id()));
        let state = root.join("state");
        let battery = root.join("battery");
        fs::create_dir_all(&state).unwrap();
        fs::create_dir_all(&battery).unwrap();
        for (name, value) in [
            ("capacity", "85"),
            ("bypass_charging", "0"),
            ("night_charging", "0"),
            ("battery_input_suspend", "0"),
        ] {
            put(battery.join(name), value).unwrap();
        }
        put(state.join("enabled"), "1").unwrap();
        let c = Controller {
            state: state.clone(),
            battery: battery.clone(),
        };
        let worker = thread::spawn(move || run(&c));
        let mut ready = false;
        for _ in 0..100 {
            if request(&state, "status").is_ok() {
                ready = true;
                break;
            }
            thread::sleep(Duration::from_millis(10));
        }
        if !ready && worker.is_finished() {
            panic!("Monitor exited: {:?}", worker.join());
        }
        assert!(ready);
        assert_eq!(read(battery.join("bypass_charging")).unwrap(), "1");
        assert!(run(&Controller {
            state: state.clone(),
            battery: battery.clone()
        })
        .is_err());
        assert_eq!(request(&state, "stop").unwrap(), "Off");
        worker.join().unwrap().unwrap();
        assert_eq!(read(battery.join("bypass_charging")).unwrap(), "0");
        assert!(!state.join("enabled").exists());
        assert!(!state.join("control").exists());
        fs::remove_dir_all(root).unwrap();
    }
}
