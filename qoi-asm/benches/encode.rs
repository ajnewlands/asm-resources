use criterion::{Criterion, black_box, criterion_group, criterion_main};
use std::alloc::{Layout, alloc};

unsafe extern "C" {
    fn qoi_encode_ref(data: *const u8, width: u32, height: u32, out: *mut *mut u8) -> i64;
}

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

struct TestImage {
    ptr: *mut u8,
    layout: Layout,
    slice: &'static [u8],
    w: u32,
    h: u32,
}

impl TestImage {
    fn from_pixels(pixels: &[u8], w: u32, h: u32) -> Self {
        let layout = Layout::from_size_align(pixels.len(), 32).unwrap();
        let ptr = unsafe { alloc(layout) };
        unsafe { std::ptr::copy_nonoverlapping(pixels.as_ptr(), ptr, pixels.len()) };
        let slice = unsafe { std::slice::from_raw_parts(ptr, pixels.len()) };
        Self { ptr, layout, slice, w, h }
    }

    fn synthetic() -> Self {
        let (w, h) = (128u32, 128u32);
        let size = (w * h * 4) as usize;
        let layout = Layout::from_size_align(size, 32).unwrap();
        let ptr = unsafe { alloc(layout) };
        let pixels = unsafe { std::slice::from_raw_parts_mut(ptr, size) };
        for y in 0..h as usize {
            for x in 0..w as usize {
                let i = (y * w as usize + x) * 4;
                pixels[i] = (x * 2) as u8;
                pixels[i + 1] = (y * 2) as u8;
                pixels[i + 2] = ((x + y) % 256) as u8;
                pixels[i + 3] = 255;
            }
        }
        let slice = unsafe { std::slice::from_raw_parts(ptr, size) };
        Self { ptr, layout, slice, w, h }
    }
}

impl Drop for TestImage {
    fn drop(&mut self) {
        unsafe { std::alloc::dealloc(self.ptr, self.layout) };
    }
}

fn bench_image(c: &mut Criterion, name: &str, img: &TestImage) {
    let mut group = c.benchmark_group(name);

    group.bench_function("ref", |b| {
        b.iter(|| {
            let mut out_ptr: *mut u8 = std::ptr::null_mut();
            let len = unsafe {
                qoi_encode_ref(black_box(img.ptr), img.w, img.h, &mut out_ptr)
            };
            assert!(len > 0);
            unsafe { libc::free(out_ptr as *mut _) };
        });
    });

    group.bench_function("crate", |b| {
        b.iter(|| {
            let _ = qoi::encode_to_vec(black_box(img.slice), img.w, img.h).unwrap();
        });
    });

    group.bench_function("asm", |b| {
        b.iter(|| {
            let mut out_ptr: *mut u8 = std::ptr::null_mut();
            let len = unsafe {
                qoi_asm::qoi_encode_asm(black_box(img.ptr), img.w, img.h, &mut out_ptr)
            };
            assert!(len > 0);
            unsafe { libc::free(out_ptr as *mut _) };
        });
    });

    group.finish();
}

fn bench_all(c: &mut Criterion) {
    let base = concat!(env!("CARGO_MANIFEST_DIR"), "/qoi_test_images/");
    let names = [
        "dice", "edgecase", "kodim10", "kodim23",
        "qoi_logo", "testcard", "testcard_rgba", "wikipedia_008",
    ];

    let synthetic = TestImage::synthetic();
    bench_image(c, "synthetic", &synthetic);

    for name in &names {
        let (pixels, w, h) = decode_png(&format!("{}{}.png", base, name));
        let img = TestImage::from_pixels(&pixels, w, h);
        bench_image(c, name, &img);
    }
}

criterion_group!(benches, bench_all);
criterion_main!(benches);
