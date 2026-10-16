// Minimal libyuv stub for libavif v1.4.2.
//
// libavif's src/scale.c includes <libyuv.h> unconditionally. This project
// never uses the scaling path (images are decoded at their native size), so
// the stub only declares the symbols scale.c references; the corresponding
// implementations (libyuv_stub.c) always return failure, which makes
// avifImageScaleWithLimit() surface AVIF_RESULT_UNKNOWN_ERROR if it is ever
// reached. All other libyuv entry points in libavif (reformat_libyuv.c) are
// compiled out because AVIF_LIBYUV_ENABLED is not defined.
#ifndef AVIF_LIBYUV_STUB_H_
#define AVIF_LIBYUV_STUB_H_

#include <stdint.h>

#define LIBYUV_VERSION 1880

enum FilterMode {
    kFilterNone = 0,
    kFilterLinear,
    kFilterBilinear,
    kFilterBox
};

#ifdef __cplusplus
extern "C" {
#endif

int ScalePlane(const uint8_t * src,
               int src_stride,
               int src_width,
               int src_height,
               uint8_t * dst,
               int dst_stride,
               int dst_width,
               int dst_height,
               enum FilterMode filtering);

int ScalePlane_12(const uint16_t * src,
                  int src_stride,
                  int src_width,
                  int src_height,
                  uint16_t * dst,
                  int dst_stride,
                  int dst_width,
                  int dst_height,
                  enum FilterMode filtering);

int ScalePlane_16(const uint16_t * src,
                  int src_stride,
                  int src_width,
                  int src_height,
                  uint16_t * dst,
                  int dst_stride,
                  int dst_width,
                  int dst_height,
                  enum FilterMode filtering);

#ifdef __cplusplus
}
#endif

#endif // AVIF_LIBYUV_STUB_H_
