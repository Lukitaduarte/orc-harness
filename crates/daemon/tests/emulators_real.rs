//! Real simulator/emulator round trips. They boot devices on this Mac, so
//! they only run on demand:
//! cargo test -p orc-daemon --test emulators_real -- --ignored --nocapture

use std::time::{Duration, Instant};

use orc_daemon::devices::Devices;
use orc_protocol::{DaemonMessage, EmulatorAction};

fn frame(rx: &mut tokio::sync::broadcast::Receiver<DaemonMessage>, id: &str, within: Duration) -> Option<(u32, u32)> {
    let until = Instant::now() + within;
    while Instant::now() < until {
        match rx.try_recv() {
            Ok(DaemonMessage::EmulatorFrame { id: got, width, height, image }) if got == id && !image.is_empty() => {
                return Some((width, height));
            }
            Ok(_) => {}
            Err(_) => std::thread::sleep(Duration::from_millis(100)),
        }
    }
    None
}

fn round_trip(platform: &str, boot_for: Duration) {
    let d = Devices::new();
    let list = d.list();
    println!("{list:#?}");
    let Some(dev) = list.iter().find(|e| e.platform == platform) else {
        println!("sem {platform} aqui");
        return;
    };
    let was_on = dev.state == "on";
    d.boot(&dev.id).unwrap_or_else(|e| println!("boot: {e}"));
    let until = Instant::now() + boot_for;
    while d.list().iter().find(|e| e.id == dev.id).map(|e| e.state.as_str()) != Some("on") {
        assert!(Instant::now() < until, "{} não ligou", dev.id);
        std::thread::sleep(Duration::from_secs(2));
    }
    let (tx, mut rx) = tokio::sync::broadcast::channel(64);
    d.watch(&dev.id, tx).unwrap();
    let size = frame(&mut rx, &dev.id, Duration::from_secs(30)).expect("nenhum frame");
    println!("{}: frame {size:?}", dev.id);
    d.act(&dev.id, EmulatorAction::Key { key: "home".into() }).unwrap();
    d.act(&dev.id, EmulatorAction::Tap { x: 0.5, y: 0.5 }).unwrap();
    d.act(&dev.id, EmulatorAction::Swipe { x1: 0.5, y1: 0.8, x2: 0.5, y2: 0.3 }).unwrap();
    assert!(frame(&mut rx, &dev.id, Duration::from_secs(10)).is_some(), "parou de mandar frames");
    d.unwatch(&dev.id);
    if !was_on {
        d.shutdown(&dev.id).unwrap();
    }
}

#[test]
#[ignore]
fn ios_simulator_streams_and_takes_taps() {
    round_trip("ios", Duration::from_secs(120));
}

#[test]
#[ignore]
fn android_emulator_streams_and_takes_taps() {
    round_trip("android", Duration::from_secs(240));
}
