use serde::Deserialize;
use std::sync::Mutex;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager};
use tauri_plugin_clipboard_manager::ClipboardExt;

const TRAY_ID: &str = "main";
const OPEN: &str = "open";
const QUIT: &str = "quit";
const CONSOLE_PREFIX: &str = "console:";
const COPY_PREFIX: &str = "copy:";

#[derive(Default)]
pub struct LastPayload(Mutex<Vec<u8>>);

#[derive(Deserialize, Default)]
struct Devices {
    nerves: Vec<Device>,
    other: Vec<Device>,
}

#[derive(Deserialize)]
struct Device {
    label: String,
    console: String,
    copy: Vec<CopyItem>,
}

#[derive(Deserialize)]
struct CopyItem {
    label: String,
    value: String,
}

pub fn create(app: &AppHandle) -> tauri::Result<()> {
    app.manage(LastPayload::default());

    let builder = TrayIconBuilder::with_id(TRAY_ID)
        .tooltip("Nerves Desktop")
        .menu(&build_menu(app, &Devices::default())?)
        .on_menu_event(|app, event| handle_menu_event(app, event.id().as_ref()));

    with_icon(app, builder).build(app)?;
    Ok(())
}

// A template image lets macOS tint the icon to match the menu bar.
#[cfg(target_os = "macos")]
fn with_icon(
    _app: &AppHandle,
    builder: TrayIconBuilder<tauri::Wry>,
) -> TrayIconBuilder<tauri::Wry> {
    builder
        .icon(tauri::include_image!("icons/tray-template.png"))
        .icon_as_template(true)
}

#[cfg(not(target_os = "macos"))]
fn with_icon(app: &AppHandle, builder: TrayIconBuilder<tauri::Wry>) -> TrayIconBuilder<tauri::Wry> {
    match app.default_window_icon() {
        Some(icon) => builder.icon(icon.clone()),
        None => builder,
    }
}

pub fn update(app: &AppHandle, payload: &[u8]) {
    let state = app.state::<LastPayload>();
    let mut last = state.0.lock().unwrap();

    // Scans repeat every few seconds; replacing an unchanged menu would close it under the cursor.
    if last.as_slice() == payload {
        return;
    }

    let devices: Devices = match serde_json::from_slice(payload) {
        Ok(devices) => devices,
        Err(error) => {
            eprintln!("[rust] invalid tray payload: {error}");
            return;
        }
    };

    *last = payload.to_vec();

    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        let Some(tray) = handle.tray_by_id(TRAY_ID) else {
            return;
        };

        match build_menu(&handle, &devices) {
            Ok(menu) => {
                let _ = tray.set_menu(Some(menu));
            }
            Err(error) => eprintln!("[rust] failed to build tray menu: {error}"),
        }
    });
}

fn build_menu(app: &AppHandle, devices: &Devices) -> tauri::Result<Menu<tauri::Wry>> {
    let menu = Menu::new(app)?;

    menu.append(&MenuItem::with_id(
        app,
        OPEN,
        "Open Nerves Desktop",
        true,
        None::<&str>,
    )?)?;
    menu.append(&PredefinedMenuItem::separator(app)?)?;

    if devices.nerves.is_empty() {
        menu.append(&MenuItem::new(
            app,
            "No Nerves devices found",
            false,
            None::<&str>,
        )?)?;
    }

    for device in &devices.nerves {
        menu.append(&device_menu(app, device)?)?;
    }

    if !devices.other.is_empty() {
        let other = Submenu::new(app, "Other Devices", true)?;

        for device in &devices.other {
            other.append(&device_menu(app, device)?)?;
        }

        menu.append(&PredefinedMenuItem::separator(app)?)?;
        menu.append(&other)?;
    }

    menu.append(&PredefinedMenuItem::separator(app)?)?;
    menu.append(&MenuItem::with_id(
        app,
        QUIT,
        "Quit Nerves Desktop",
        true,
        None::<&str>,
    )?)?;

    Ok(menu)
}

fn device_menu(app: &AppHandle, device: &Device) -> tauri::Result<Submenu<tauri::Wry>> {
    let submenu = Submenu::new(app, &device.label, true)?;

    submenu.append(&MenuItem::with_id(
        app,
        format!("{CONSOLE_PREFIX}{}", device.console),
        "Open Console",
        true,
        None::<&str>,
    )?)?;

    for item in &device.copy {
        submenu.append(&MenuItem::with_id(
            app,
            format!("{COPY_PREFIX}{}", item.value),
            &item.label,
            true,
            None::<&str>,
        )?)?;
    }

    Ok(submenu)
}

fn handle_menu_event(app: &AppHandle, id: &str) {
    if id == OPEN {
        crate::show_main_window(app);
    } else if id == QUIT {
        app.exit(0);
    } else if let Some(path) = id.strip_prefix(CONSOLE_PREFIX) {
        crate::open_path(app, path);
    } else if let Some(value) = id.strip_prefix(COPY_PREFIX) {
        if let Err(error) = app.clipboard().write_text(value) {
            eprintln!("[rust] failed to copy to clipboard: {error}");
        }
    }
}
