fn main() {
    cxx_qt_build::CxxQtBuilder::new()
        .file("src/backend.rs")
        .build();
}
