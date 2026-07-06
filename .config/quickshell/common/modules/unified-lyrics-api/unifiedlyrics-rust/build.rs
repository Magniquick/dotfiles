use std::path::Path;

fn main() {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR");
    let header = Path::new(&crate_dir).join("../cpp/unifiedlyrics_api.h");
    cbindgen::generate(&crate_dir)
        .expect("cbindgen failed to generate unifiedlyrics_api.h")
        .write_to_file(&header);
    println!("cargo:rerun-if-changed=src");
    println!("cargo:rerun-if-changed=cbindgen.toml");
}
