use serde_json::json;
use tauri::Manager;
use tauri_plugin_dialog::DialogExt;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let app_handle = app.handle().clone();
            let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen");
            app.manage(pubsub.clone());

            let pubsub_clone = pubsub.clone();
            let app_handle_clone = app_handle.clone();

            // Handle messages from Elixir in a separate task to avoid blocking setup
            tauri::async_runtime::spawn(async move {
                let pubsub_inner = pubsub_clone.clone();
                pubsub_clone.subscribe("messages", move |msg| {
                    if msg == b"ready" {
                        // Gather host info once Elixir is ready
                        let os_info = json!({
                            "platform": tauri_plugin_os::platform(),
                            "arch": tauri_plugin_os::arch(),
                            "version": tauri_plugin_os::version(),
                            "locale": tauri_plugin_os::locale(),
                        });

                        // Broadcast host info back to Elixir
                        let _ = pubsub_inner.broadcast("host_info", os_info.to_string().as_bytes());

                        // Create the main window
                        create_window(&app_handle_clone);
                    } else if msg == b"open_file_dialog" {
                        let ps = pubsub_inner.clone();
                        app_handle_clone
                            .dialog()
                            .file()
                            .add_filter("Firmware", &["fw"])
                            .pick_file(move |file_path| {
                                if let Some(path) = file_path {
                                    let path_str = path.to_string();
                                    let _ = ps.broadcast("file_dialog_result", path_str.as_bytes());
                                }
                            });
                    } else {
                        println!("[rust] received unknown message: {}", String::from_utf8_lossy(msg));
                    }
                });
            });

            // Start Elixir in background
            let app_handle_exit = app_handle.clone();
            tauri::async_runtime::spawn_blocking(move || {
                let mut command = elixir_command();
                command.env("ELIXIRKIT_PUBSUB", pubsub.url());
                let status = command.status().expect("failed to start Elixir");

                app_handle_exit.exit(status.code().unwrap_or(1));
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn create_window(app_handle: &tauri::AppHandle) {
    let n = app_handle.webview_windows().len() + 1;
    let url = tauri::WebviewUrl::External("http://127.0.0.1:4000".parse().unwrap());
    tauri::WebviewWindowBuilder::new(app_handle, format!("window-{}", n), url)
        .title("Nerves Desktop")
        .min_inner_size(800.0, 600.0)
        .maximized(true)
        .build()
        .unwrap();
}

fn elixir_command() -> std::process::Command {
    let mut command = elixirkit::mix("phx.server", &[]);
    command.current_dir("..");
    command
}
