use std::process::Command;

fn main() {
    let out_dir = std::env::var("OUT_DIR").unwrap();
    let obj = format!("{}/qoi_encode.o", out_dir);

    let status = Command::new("nasm")
        .args(["-f", "elf64", "src/qoi_encode.asm", "-o", &obj])
        .status()
        .expect("failed to run nasm");

    assert!(status.success(), "nasm failed");

    println!("cargo:rustc-link-arg={}", obj);
    println!("cargo:rerun-if-changed=src/qoi_encode.asm");

    // Compile reference C encoder
    cc::Build::new()
        .file("src/qoi_ref.c")
        .include("/usr/include")
        .compile("qoi_ref");

    println!("cargo:rerun-if-changed=src/qoi_ref.c");
}
