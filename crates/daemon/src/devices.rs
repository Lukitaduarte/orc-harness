//! Android emulators and iOS simulators in panes: booted without a window,
//! their screens streamed to clients, driven with taps, swipes and keys.
//!
//! Android goes through the SDK (`emulator -no-window`, `adb exec-out
//! screencap`, `adb shell input`); iOS through `xcrun simctl` (boot and
//! shutdown, no Simulator.app) and AXe (`axe stream-video`, `axe tap`…).
//! Agents use the same devices with their own tools; the PreToolUse hook
//! sees those calls and marks the device in use by that session.

use std::collections::HashMap;
use std::io::Read;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use base64::Engine;
use orc_protocol::{DaemonMessage, EmulatorAction, EmulatorInfo};
use tokio::sync::broadcast;

/// A device counts as in use this long after an agent's last call to it.
pub const ACTIVE_FOR: Duration = Duration::from_secs(5);

#[derive(Default)]
struct State {
    /// Streams running, by device id; clearing the flag stops one.
    watching: HashMap<String, Arc<AtomicBool>>,
    /// Emulators this daemon started, by AVD name.
    emulators: HashMap<String, Child>,
    /// iOS screen size in points (taps are in points), by UDID.
    points: HashMap<String, (f64, f64)>,
    /// Last agent use: device id → (session, when).
    used: HashMap<String, (String, Instant)>,
}

#[derive(Clone)]
pub struct Devices {
    sdk: Option<PathBuf>,
    axe: Option<PathBuf>,
    state: Arc<Mutex<State>>,
}

fn which(name: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .chain(["/opt/homebrew/bin".into(), "/usr/local/bin".into()])
        .map(|d| d.join(name))
        .find(|p| p.is_file())
}

fn run(cmd: &mut Command) -> std::io::Result<String> {
    let out = cmd.stdin(Stdio::null()).stderr(Stdio::piped()).output()?;
    if !out.status.success() {
        return Err(std::io::Error::other(format!("{:?}: {}", cmd.get_program(), String::from_utf8_lossy(&out.stderr).trim())));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// Width and height of a PNG or JPEG.
pub fn image_size(b: &[u8]) -> Option<(u32, u32)> {
    if b.starts_with(b"\x89PNG") && b.len() >= 24 {
        let n = |i: usize| u32::from_be_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]]);
        return Some((n(16), n(20)));
    }
    if !b.starts_with(&[0xFF, 0xD8]) {
        return None;
    }
    let mut i = 2;
    while i + 9 < b.len() {
        if b[i] != 0xFF {
            i += 1;
            continue;
        }
        let marker = b[i + 1];
        let len = u16::from_be_bytes([b[i + 2], b[i + 3]]) as usize;
        // SOF0..SOF15 except DHT (C4), JPG (C8) and DAC (CC).
        if (0xC0..=0xCF).contains(&marker) && ![0xC4, 0xC8, 0xCC].contains(&marker) {
            let h = u16::from_be_bytes([b[i + 5], b[i + 6]]) as u32;
            let w = u16::from_be_bytes([b[i + 7], b[i + 8]]) as u32;
            return Some((w, h));
        }
        i += 2 + len;
    }
    None
}

/// Splits whole JPEGs off the front of an MJPEG byte stream.
pub fn take_jpegs(buf: &mut Vec<u8>) -> Vec<Vec<u8>> {
    let mut out = Vec::new();
    loop {
        let Some(start) = buf.windows(2).position(|w| w == [0xFF, 0xD8]) else {
            buf.clear();
            break;
        };
        let Some(end) = buf[start + 2..].windows(2).position(|w| w == [0xFF, 0xD9]).map(|e| start + 2 + e + 2) else {
            buf.drain(..start);
            break;
        };
        out.push(buf[start..end].to_vec());
        buf.drain(..end);
    }
    out
}

/// `adb shell input text` takes no spaces or shell specials as they are.
pub fn adb_text(text: &str) -> String {
    text.chars()
        .map(|c| match c {
            ' ' => "%s".to_string(),
            c if c.is_ascii_alphanumeric() || ".,-_@/:".contains(c) => c.to_string(),
            c => format!("\\{c}"),
        })
        .collect()
}

/// Which platform a tool call drives, if any: commands that run adb,
/// emulator, simctl or AXe, and MCP tools named for mobile devices.
pub fn platform_of_call(tool: &str, input: &serde_json::Value) -> Option<&'static str> {
    if tool == "Bash" {
        let cmd = input.get("command").and_then(|c| c.as_str()).unwrap_or_default();
        let words: Vec<&str> = cmd.split(|c: char| c.is_whitespace() || c == ';' || c == '&' || c == '|').collect();
        let has = |w: &str| words.iter().any(|x| x.rsplit('/').next() == Some(w));
        if has("simctl") || has("axe") {
            return Some("ios");
        }
        if has("adb") || has("emulator") {
            return Some("android");
        }
        return None;
    }
    let t = tool.to_ascii_lowercase();
    if !t.starts_with("mcp__") {
        return None;
    }
    if t.contains("ios") || t.contains("simulator") || t.contains("xcode") {
        Some("ios")
    } else if t.contains("android") || t.contains("adb") {
        Some("android")
    } else if t.contains("mobile") || t.contains("device") {
        Some("any")
    } else {
        None
    }
}

impl Devices {
    pub fn new() -> Self {
        let sdk = std::env::var_os("ANDROID_HOME")
            .or_else(|| std::env::var_os("ANDROID_SDK_ROOT"))
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join("Library/Android/sdk")))
            .filter(|p| p.join("platform-tools/adb").is_file());
        Self { sdk, axe: which("axe"), state: Arc::default() }
    }

    fn adb(&self) -> Option<PathBuf> {
        self.sdk.as_ref().map(|s| s.join("platform-tools/adb"))
    }

    /// Running emulators: AVD name → adb serial.
    fn android_serials(&self) -> HashMap<String, String> {
        let Some(adb) = self.adb() else { return HashMap::new() };
        let Ok(out) = run(Command::new(&adb).arg("devices")) else { return HashMap::new() };
        out.lines()
            .filter_map(|l| l.split_once('\t'))
            .filter(|(serial, _)| serial.starts_with("emulator-"))
            .filter_map(|(serial, _)| {
                let name = run(Command::new(&adb).args(["-s", serial, "emu", "avd", "name"])).ok()?;
                Some((name.lines().next()?.trim().to_string(), serial.to_string()))
            })
            .collect()
    }

    fn android_booted(&self, serial: &str) -> bool {
        let Some(adb) = self.adb() else { return false };
        run(Command::new(adb).args(["-s", serial, "shell", "getprop", "sys.boot_completed"])).is_ok_and(|o| o.trim() == "1")
    }

    /// Every device you could open: iOS simulators and Android AVDs.
    pub fn list(&self) -> Vec<EmulatorInfo> {
        let mut out = Vec::new();
        if let Ok(raw) = run(Command::new("xcrun").args(["simctl", "list", "-j", "devices", "available"])) {
            let doc: serde_json::Value = serde_json::from_str(&raw).unwrap_or_default();
            for (runtime, devices) in doc["devices"].as_object().into_iter().flatten() {
                let Some(version) = runtime.rsplit('.').next().filter(|r| r.starts_with("iOS-")) else { continue };
                for d in devices.as_array().into_iter().flatten() {
                    let (Some(udid), Some(name)) = (d["udid"].as_str(), d["name"].as_str()) else { continue };
                    let state = match d["state"].as_str() {
                        Some("Booted") => "on",
                        Some("Booting") => "booting",
                        _ => "off",
                    };
                    out.push(EmulatorInfo {
                        id: format!("ios:{udid}"),
                        platform: "ios".into(),
                        name: format!("{name} ({})", version.trim_start_matches("iOS-").replace('-', ".")),
                        state: state.into(),
                    });
                }
            }
        }
        if let Some(sdk) = &self.sdk
            && let Ok(avds) = run(Command::new(sdk.join("emulator/emulator")).arg("-list-avds"))
        {
            let serials = self.android_serials();
            let starting: Vec<String> = self.state.lock().unwrap().emulators.keys().cloned().collect();
            for avd in avds.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with("INFO")) {
                let state = match serials.get(avd) {
                    Some(serial) if self.android_booted(serial) => "on",
                    Some(_) => "booting",
                    None if starting.iter().any(|s| s == avd) => "booting",
                    None => "off",
                };
                out.push(EmulatorInfo { id: format!("android:{avd}"), platform: "android".into(), name: avd.replace('_', " "), state: state.into() });
            }
        }
        out
    }

    fn serial(&self, avd: &str) -> Result<String, String> {
        self.android_serials().remove(avd).ok_or_else(|| format!("o emulador {avd} não está ligado"))
    }

    pub fn boot(&self, id: &str) -> Result<(), String> {
        match id.split_once(':') {
            Some(("ios", udid)) => {
                // Already on is fine (CoreSimulator error 405).
                if let Err(e) = run(Command::new("xcrun").args(["simctl", "boot", udid]))
                    && !e.to_string().contains("code=405")
                {
                    return Err(e.to_string());
                }
            }
            Some(("android", avd)) => {
                let sdk = self.sdk.as_ref().ok_or("Android SDK não encontrado (ANDROID_HOME)")?;
                let mut state = self.state.lock().unwrap();
                if !state.emulators.contains_key(avd) {
                    let child = Command::new(sdk.join("emulator/emulator"))
                        .args(["-avd", avd, "-no-window", "-no-audio", "-no-boot-anim"])
                        .stdin(Stdio::null())
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn()
                        .map_err(|e| e.to_string())?;
                    state.emulators.insert(avd.to_string(), child);
                }
            }
            _ => return Err(format!("dispositivo desconhecido: {id}")),
        }
        Ok(())
    }

    pub fn shutdown(&self, id: &str) -> Result<(), String> {
        self.unwatch(id);
        match id.split_once(':') {
            Some(("ios", udid)) => {
                run(Command::new("xcrun").args(["simctl", "shutdown", udid])).map_err(|e| e.to_string())?;
            }
            Some(("android", avd)) => {
                if let (Some(adb), Ok(serial)) = (self.adb(), self.serial(avd)) {
                    let _ = run(Command::new(adb).args(["-s", &serial, "emu", "kill"]));
                }
                if let Some(mut child) = self.state.lock().unwrap().emulators.remove(avd) {
                    let _ = child.wait();
                }
            }
            _ => return Err(format!("dispositivo desconhecido: {id}")),
        }
        Ok(())
    }

    pub fn unwatch(&self, id: &str) {
        if let Some(flag) = self.state.lock().unwrap().watching.remove(id) {
            flag.store(false, Ordering::Relaxed);
        }
    }

    /// Streams the screen as frames until `unwatch` (or the device stops).
    pub fn watch(&self, id: &str, events: broadcast::Sender<DaemonMessage>) -> Result<(), String> {
        let flag = Arc::new(AtomicBool::new(true));
        if let Some(old) = self.state.lock().unwrap().watching.insert(id.to_string(), flag.clone()) {
            old.store(false, Ordering::Relaxed);
        }
        let send = move |id: &str, image: &[u8]| {
            let Some((width, height)) = image_size(image) else { return };
            let image = base64::engine::general_purpose::STANDARD.encode(image);
            let _ = events.send(DaemonMessage::EmulatorFrame { id: id.to_string(), image, width, height });
        };
        let id = id.to_string();
        match id.split_once(':') {
            Some(("ios", udid)) => {
                let axe = self.axe.clone().ok_or("instale o AXe para ver o simulador: brew install cameroncooke/axe/axe")?;
                self.ios_points(udid);
                let mut child = Command::new(axe)
                    .args(["stream-video", "--udid", udid, "--format", "mjpeg", "--fps", "10", "--quality", "70", "--scale", "0.5"])
                    .stdin(Stdio::null())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::null())
                    .spawn()
                    .map_err(|e| e.to_string())?;
                let mut out = child.stdout.take().expect("piped");
                std::thread::spawn(move || {
                    let (mut buf, mut chunk) = (Vec::new(), [0u8; 64 * 1024]);
                    while flag.load(Ordering::Relaxed) {
                        match out.read(&mut chunk) {
                            Ok(0) | Err(_) => break,
                            Ok(n) => buf.extend_from_slice(&chunk[..n]),
                        }
                        // Only the newest frame matters.
                        if let Some(last) = take_jpegs(&mut buf).pop() {
                            send(&id, &last);
                        }
                    }
                    let _ = child.kill();
                    let _ = child.wait();
                });
            }
            Some(("android", avd)) => {
                let adb = self.adb().ok_or("Android SDK não encontrado (ANDROID_HOME)")?;
                let serial = self.serial(avd)?;
                std::thread::spawn(move || {
                    // screencap is a still: a few a second, as fast as it goes.
                    while flag.load(Ordering::Relaxed) {
                        let started = Instant::now();
                        match Command::new(&adb).args(["-s", &serial, "exec-out", "screencap", "-p"]).stdin(Stdio::null()).stderr(Stdio::null()).output() {
                            Ok(o) if o.status.success() && !o.stdout.is_empty() => send(&id, &o.stdout),
                            _ => std::thread::sleep(Duration::from_secs(1)),
                        }
                        std::thread::sleep(Duration::from_millis(150).saturating_sub(started.elapsed()));
                    }
                });
            }
            _ => return Err(format!("dispositivo desconhecido: {id}")),
        }
        Ok(())
    }

    /// The simulator's screen in points, from its accessibility tree.
    fn ios_points(&self, udid: &str) -> (f64, f64) {
        if let Some(p) = self.state.lock().unwrap().points.get(udid) {
            return *p;
        }
        let measured = self.axe.as_ref().and_then(|axe| {
            let raw = run(Command::new(axe).args(["describe-ui", "--udid", udid])).ok()?;
            let doc: serde_json::Value = serde_json::from_str(&raw).ok()?;
            let root = if doc.is_array() { doc[0].clone() } else { doc };
            let f = &root["frame"];
            Some((f["width"].as_f64()?, f["height"].as_f64()?))
        });
        let p = measured.unwrap_or((402.0, 874.0));
        if measured.is_some() {
            self.state.lock().unwrap().points.insert(udid.to_string(), p);
        }
        p
    }

    /// Your input. Positions are fractions of the screen (0 to 1).
    pub fn act(&self, id: &str, action: EmulatorAction) -> Result<(), String> {
        let err = |e: std::io::Error| e.to_string();
        match id.split_once(':') {
            Some(("ios", udid)) => {
                let axe = self.axe.clone().ok_or("instale o AXe: brew install cameroncooke/axe/axe")?;
                let (w, h) = self.ios_points(udid);
                let at = |x: f64, y: f64| ((x * w).round().to_string(), (y * h).round().to_string());
                let mut cmd = Command::new(axe);
                match action {
                    EmulatorAction::Tap { x, y } => {
                        let (x, y) = at(x, y);
                        cmd.args(["tap", "-x", &x, "-y", &y]);
                    }
                    EmulatorAction::Swipe { x1, y1, x2, y2 } => {
                        let ((a, b), (c, d)) = (at(x1, y1), at(x2, y2));
                        cmd.args(["swipe", "--start-x", &a, "--start-y", &b, "--end-x", &c, "--end-y", &d, "--duration", "0.3"]);
                    }
                    EmulatorAction::Text { text } => {
                        cmd.args(["type", &text]);
                    }
                    EmulatorAction::Key { key } => match key.as_str() {
                        "home" => {
                            cmd.args(["button", "home"]);
                        }
                        "lock" => {
                            cmd.args(["button", "lock"]);
                        }
                        // HID usage codes.
                        "enter" => {
                            cmd.args(["key", "40"]);
                        }
                        "backspace" => {
                            cmd.args(["key", "42"]);
                        }
                        _ => return Ok(()),
                    },
                    _ => return Ok(()),
                }
                cmd.args(["--udid", udid]);
                // Right after a button or an animation the screen has no
                // target for a moment: once more, shortly after.
                if let Err(e) = run(&mut cmd) {
                    if !e.to_string().contains("No translation object") {
                        return Err(e.to_string());
                    }
                    std::thread::sleep(Duration::from_millis(600));
                    run(&mut cmd).map_err(err)?;
                }
            }
            Some(("android", avd)) => {
                let adb = self.adb().ok_or("Android SDK não encontrado")?;
                let serial = self.serial(avd)?;
                // Screen in pixels, for the fractions.
                let size = run(Command::new(&adb).args(["-s", &serial, "shell", "wm", "size"])).map_err(err)?;
                let (w, h) = size
                    .lines()
                    .rev()
                    .find_map(|l| l.rsplit_once(": ")?.1.trim().split_once('x').map(|(a, b)| (a.parse::<f64>().ok(), b.parse::<f64>().ok())))
                    .and_then(|(a, b)| Some((a?, b?)))
                    .unwrap_or((1080.0, 2400.0));
                let px = |x: f64, y: f64| ((x * w).round().to_string(), (y * h).round().to_string());
                let mut cmd = Command::new(adb);
                cmd.args(["-s", &serial, "shell", "input"]);
                match action {
                    EmulatorAction::Tap { x, y } => {
                        let (x, y) = px(x, y);
                        cmd.args(["tap", &x, &y]);
                    }
                    EmulatorAction::Swipe { x1, y1, x2, y2 } => {
                        let ((a, b), (c, d)) = (px(x1, y1), px(x2, y2));
                        cmd.args(["swipe", &a, &b, &c, &d, "300"]);
                    }
                    EmulatorAction::Text { text } => {
                        cmd.args(["text", &adb_text(&text)]);
                    }
                    EmulatorAction::Key { key } => {
                        let code = match key.as_str() {
                            "home" => "3",
                            "back" => "4",
                            "enter" => "66",
                            "backspace" => "67",
                            "lock" => "26",
                            "recents" => "187",
                            _ => return Ok(()),
                        };
                        cmd.args(["keyevent", code]);
                    }
                    _ => return Ok(()),
                }
                run(&mut cmd).map_err(err)?;
            }
            _ => return Err(format!("dispositivo desconhecido: {id}")),
        }
        Ok(())
    }

    /// Notes an agent's tool call that drives a device (from the hook).
    pub fn note_call(&self, session: &str, tool: &str, input: &serde_json::Value) {
        let Some(platform) = platform_of_call(tool, input) else { return };
        let text = input.to_string();
        let on: Vec<EmulatorInfo> = self.list().into_iter().filter(|d| d.state != "off").collect();
        // The one the call names (UDID or AVD), else the running ones of
        // that platform.
        let named: Vec<&EmulatorInfo> = on.iter().filter(|d| text.contains(d.id.split_once(':').map_or("", |x| x.1))).collect();
        let hit: Vec<&EmulatorInfo> = if named.is_empty() {
            on.iter().filter(|d| platform == "any" || d.platform == platform).collect()
        } else {
            named
        };
        let mut state = self.state.lock().unwrap();
        for d in hit {
            state.used.insert(d.id.clone(), (session.to_string(), Instant::now()));
        }
    }

    /// Tells clients when an agent starts and stops driving a device.
    pub async fn report_use(self, events: broadcast::Sender<DaemonMessage>) {
        let mut shown: HashMap<String, String> = HashMap::new();
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        loop {
            tick.tick().await;
            let now: HashMap<String, String> = self
                .state
                .lock()
                .unwrap()
                .used
                .iter()
                .filter(|(_, (_, at))| at.elapsed() < ACTIVE_FOR)
                .map(|(d, (s, _))| (d.clone(), s.clone()))
                .collect();
            for (id, session) in &now {
                if shown.get(id) != Some(session) {
                    let _ = events.send(DaemonMessage::EmulatorUse { id: id.clone(), session_id: Some(session.clone()) });
                }
            }
            for id in shown.keys().filter(|d| !now.contains_key(*d)) {
                let _ = events.send(DaemonMessage::EmulatorUse { id: id.clone(), session_id: None });
            }
            shown = now;
        }
    }
}

impl Default for Devices {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn sizes_of_png_and_jpeg() {
        let mut png = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR".to_vec();
        png.extend_from_slice(&1080u32.to_be_bytes());
        png.extend_from_slice(&2400u32.to_be_bytes());
        assert_eq!(image_size(&png), Some((1080, 2400)));
        // SOI, APP0 (len 4), SOF0 with height 874 and width 402.
        let jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 11, 8, 0x03, 0x6A, 0x01, 0x92, 3, 0, 0, 0];
        assert_eq!(image_size(&jpeg), Some((402, 874)));
        assert_eq!(image_size(b"nope"), None);
    }

    #[test]
    fn whole_jpegs_come_off_a_stream() {
        let mut buf = vec![1, 2, 0xFF, 0xD8, 9, 0xFF, 0xD9, 0xFF, 0xD8, 7, 0xFF, 0xD9, 0xFF, 0xD8, 5];
        let frames = take_jpegs(&mut buf);
        assert_eq!(frames, [vec![0xFF, 0xD8, 9, 0xFF, 0xD9], vec![0xFF, 0xD8, 7, 0xFF, 0xD9]]);
        assert_eq!(buf, [0xFF, 0xD8, 5], "a partial frame waits for the rest");
    }

    #[test]
    fn agent_calls_that_drive_devices() {
        let bash = |c: &str| json!({ "command": c });
        assert_eq!(platform_of_call("Bash", &bash("xcrun simctl io booted screenshot a.png")), Some("ios"));
        assert_eq!(platform_of_call("Bash", &bash("axe tap -x 1 -y 2 --udid X")), Some("ios"));
        assert_eq!(platform_of_call("Bash", &bash("~/sdk/platform-tools/adb shell input tap 1 2")), Some("android"));
        assert_eq!(platform_of_call("Bash", &bash("cd app && flutter test")), None);
        assert_eq!(platform_of_call("Bash", &bash("cat readme && grep adbc x")), None);
        assert_eq!(platform_of_call("mcp__mobile__tap", &json!({})), Some("any"));
        assert_eq!(platform_of_call("mcp__ios-simulator__ui_tap", &json!({})), Some("ios"));
        assert_eq!(platform_of_call("Read", &json!({ "file_path": "adb" })), None);
    }

    #[test]
    fn text_for_adb_input() {
        assert_eq!(adb_text("oi mundo!"), "oi%smundo\\!");
        assert_eq!(adb_text("a@b.com"), "a@b.com");
    }
}
