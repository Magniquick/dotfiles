use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("qsnative"))
        .file("src/lib.rs")
        .build();
}
