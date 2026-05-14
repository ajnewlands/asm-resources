unsafe extern "C" {
    pub fn qoi_encode_asm(data: *const u8, width: u32, height: u32, out: *mut *mut u8) -> i64;
    pub fn qoi_encode_ref(data: *const u8, width: u32, height: u32, out: *mut *mut u8) -> i64;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::alloc::{Layout, alloc};

    fn decode_png(path: &str) -> (Vec<u8>, u32, u32) {
        let file = std::fs::File::open(path).unwrap();
        let decoder = png::Decoder::new(file);
        let mut reader = decoder.read_info().unwrap();
        let mut buf = vec![0u8; reader.output_buffer_size()];
        let info = reader.next_frame(&mut buf).unwrap();
        buf.truncate(info.buffer_size());
        let pixels = match info.color_type {
            png::ColorType::Rgba => buf,
            png::ColorType::Rgb => {
                let mut rgba = Vec::with_capacity((info.width * info.height * 4) as usize);
                for chunk in buf.chunks(3) {
                    rgba.extend_from_slice(chunk);
                    rgba.push(255);
                }
                rgba
            }
            _ => panic!("unsupported color type: {:?}", info.color_type),
        };
        (pixels, info.width, info.height)
    }

    fn run_test_image(name: &str) {
        let base = concat!(env!("CARGO_MANIFEST_DIR"), "/qoi_test_images/");
        let png_path = format!("{}{}.png", base, name);

        let (pixels, w, h) = decode_png(&png_path);

        let layout = Layout::from_size_align(pixels.len(), 32).unwrap();
        let ptr = unsafe { alloc(layout) };
        unsafe { std::ptr::copy_nonoverlapping(pixels.as_ptr(), ptr, pixels.len()) };

        // Encode with reference C encoder
        let mut ref_ptr: *mut u8 = std::ptr::null_mut();
        let ref_len = unsafe { qoi_encode_ref(ptr, w, h, &mut ref_ptr) };
        assert!(ref_len >= 0, "{}: reference encoder failed", name);

        // Encode with our ASM encoder
        let mut asm_ptr: *mut u8 = std::ptr::null_mut();
        let asm_len = unsafe { qoi_encode_asm(ptr, w, h, &mut asm_ptr) };
        assert!(asm_len > 0, "{}: asm encoder failed", name);
        assert!(!asm_ptr.is_null(), "{}: null output", name);

        let expected = unsafe { std::slice::from_raw_parts(ref_ptr, ref_len as usize) };
        let encoded = unsafe { std::slice::from_raw_parts(asm_ptr, asm_len as usize) };

        assert!(
            encoded == expected,
            "{}: encoded output mismatch (got {} bytes, expected {} bytes)",
            name,
            encoded.len(),
            expected.len()
        );

        unsafe {
            libc::free(ref_ptr as *mut _);
            libc::free(asm_ptr as *mut _);
            std::alloc::dealloc(ptr, layout);
        }
    }

    #[test] fn test_image_dice() { run_test_image("dice"); }
    #[test] fn test_image_edgecase() { run_test_image("edgecase"); }
    #[test] fn test_image_kodim10() { run_test_image("kodim10"); }
    #[test] fn test_image_kodim23() { run_test_image("kodim23"); }
    #[test] fn test_image_qoi_logo() { run_test_image("qoi_logo"); }
    #[test] fn test_image_testcard_rgba() { run_test_image("testcard_rgba"); }
    #[test] fn test_image_testcard() { run_test_image("testcard"); }
    #[test] fn test_image_wikipedia_008() { run_test_image("wikipedia_008"); }
}
