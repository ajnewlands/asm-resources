#define QOI_IMPLEMENTATION
#include "qoi.h"

// Wrapper so Rust can call the reference encoder.
// Returns encoded length, or -1 on error. Sets *out to the malloc'd buffer.
long qoi_encode_ref(const unsigned char *data, unsigned int width, unsigned int height, unsigned char **out) {
    qoi_desc desc = {
        .width = width,
        .height = height,
        .channels = 4,
        .colorspace = QOI_SRGB
    };
    int out_len = 0;
    void *encoded = qoi_encode(data, &desc, &out_len);
    if (!encoded) return -1;
    *out = encoded;
    return out_len;
}
