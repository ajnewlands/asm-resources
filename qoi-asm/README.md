# qoi-asm : x86 ASM implementation of the QOI encoder

This repo contains an assembly code implementation of the qoi encoder function (`qoi_encode_asm`) along with
a test harness and benchmark suite.

The test harness demonstrates that it produces the same inputs as the C reference encoder across the test data
set provided at https://qoiformat.org/qoi_test_images.zip. (N.B. it does not exactly match the rust QOI crate, which has an extra optimization and produces slightly different output on some tests).

The benchmark harness tests performance against the reference encoder and the Rust QOI crate.

Results of this testing:

| Test Case     | Reference Encoder | QOI Crate | ASM Encoder | Speedup |
| ------------- | ----------------- | --------- | ----------- | ------- |
| Synthetic     | 0.07769           | 0.088935  | 0.06858     | 11.7%   |
| Dice          | 1.1212            | 1.1766    | 0.91123     | 18.7%   |
| Edgecase      | 0.022584          | 0.022656  | 0.015187    | 32.8%   |
| Kodim10       | 3.555             | 2.9042    | 2.939       | -1.2%   |
| Kodim23       | 3.7214            | 2.8932    | 2.988       | -3.3%   |
| Qoi_logo      | 0.12894           | 0.13787   | 0.097672    | 24.3%   |
| testcard      | 0.14089           | 0.14017   | 0.11459     | 18.3%   |
| testcard_rgba | 0.14571           | 0.14693   | 0.12086     | 17.1%   |
| Wikipedia_009 | 8.9184            | 8.3092    | 7.2409      | 12.9%   |

In every case, the ASM implementation is quicker than the reference implementation and also quicker than the rust QOI crate for non-photographic cases.

The rust QOI crate is a tiny sliver faster on the photographic tests whilst producing slightly different output to the reference encode.

I did experiment with vectorized read ahead of "same pixel" runs, which further sped up the non-photographic case but noticeably worsened performance in photographic cases. I eventually reverted this since I could not mitigate the slowdown for photographs (which are the slowest by far to encode).

Whilst it is in general a faster encoder it's probably not fast enough to justify losing portability (and readability) versus the higher level language implementations.

## Speedup Chart

<svg xmlns="http://www.w3.org/2000/svg" width="560" height="300">
  <rect width="560" height="300" fill="#fff"/>
  <style>text{font-family:sans-serif;font-size:12px}</style>
  <line x1="280" y1="5" x2="280" y2="295" stroke="#999" stroke-width="1"/>
  <text x="165" y="23" text-anchor="end">Synthetic</text><rect x="280" y="11" width="107" height="20" fill="#1a7a1a"/><text x="390" y="26">11.7%</text>
  <text x="165" y="53" text-anchor="end">Dice</text><rect x="280" y="41" width="171" height="20" fill="#1a7a1a"/><text x="454" y="56">18.7%</text>
  <text x="165" y="83" text-anchor="end">Edgecase</text><rect x="280" y="71" width="240" height="20" fill="#1a7a1a"/><text x="523" y="86">32.8%</text>
  <text x="165" y="113" text-anchor="end">Kodim10</text><rect x="271" y="101" width="9" height="20" fill="#c0392b"/><text x="258" y="116" text-anchor="end">-1.2%</text>
  <text x="165" y="143" text-anchor="end">Kodim23</text><rect x="256" y="131" width="24" height="20" fill="#c0392b"/><text x="243" y="146" text-anchor="end">-3.3%</text>
  <text x="165" y="173" text-anchor="end">Qoi_logo</text><rect x="280" y="161" width="178" height="20" fill="#1a7a1a"/><text x="461" y="176">24.3%</text>
  <text x="165" y="203" text-anchor="end">testcard</text><rect x="280" y="191" width="134" height="20" fill="#1a7a1a"/><text x="417" y="206">18.3%</text>
  <text x="165" y="233" text-anchor="end">testcard_rgba</text><rect x="280" y="221" width="125" height="20" fill="#1a7a1a"/><text x="408" y="236">17.1%</text>
  <text x="165" y="263" text-anchor="end">Wikipedia_009</text><rect x="280" y="251" width="94" height="20" fill="#1a7a1a"/><text x="377" y="266">12.9%</text>
</svg>
