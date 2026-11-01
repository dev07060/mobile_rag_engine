fn main() {
    // Google Play requires 16 KB page support for apps targeting Android 15+.
    // NDK r27 still links with 4 KB alignment by default.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        println!("cargo:rustc-cdylib-link-arg=-Wl,-z,max-page-size=16384");
    }
}
