fn main() {
    let builder = cxx_qt_build::CxxQtBuilder::new()
        .file("src/net_stats.rs")
        .file("src/backlight.rs")
        .file("src/bluetooth.rs")
        .file("src/config_resolver.rs")
        .file("src/ical.rs")
        .file("src/idle.rs")
        .file("src/keyboard_lock.rs")
        .file("src/pacman.rs")
        .file("src/privacy.rs")
        .file("src/sys_info.rs")
        .file("src/systemd_failed.rs")
        .file("src/todoist.rs")
        .include_dir("../cpp");

    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.file("../cpp/QsNativeSystemdFailed.cpp");
        })
    };

    builder.build();
}
