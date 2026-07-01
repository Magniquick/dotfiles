fn main() {
    unsafe {
        cxx_qt_build::CxxQtBuilder::new()
            .file("src/lib.rs")
            .cc_builder(|cc| {
                cc.include("../cpp");
            })
            .build();
    }
}
