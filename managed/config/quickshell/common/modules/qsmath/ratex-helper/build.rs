fn main() {
    cxx_qt_build::CxxQtBuilder::new()
        .file("src/markdown_stream.rs")
        .build();
}
