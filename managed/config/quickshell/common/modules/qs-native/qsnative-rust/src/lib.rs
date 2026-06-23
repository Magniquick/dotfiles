use std::sync::Once;

static PANIC_HOOK: Once = Once::new();

pub fn install_panic_hook() {
    PANIC_HOOK.call_once(|| {
        std::panic::set_hook(Box::new(|info| {
            eprintln!("qs-native panic: {info}");
            std::process::abort();
        }));
    });
}

/// Convert a `usize` count to `i32`, clamping to `i32::MAX` on overflow.
pub fn count_to_i32(count: usize) -> i32 {
    count.try_into().unwrap_or(i32::MAX)
}

pub mod ai;
pub mod app_config;
pub mod backlight;
pub mod bar_module_logic;
pub mod bluetooth;
pub mod chatstore;
pub mod config_resolver;
pub mod email;
pub mod gmail;
pub mod google_auth;
pub mod ical;
pub mod idle;
pub mod mcp;
pub mod net_stats;
pub mod pacman;
pub mod privacy;
pub mod secrets;
pub mod sys_info;
pub mod systemd_failed;
pub mod todoist;
pub mod utils;
