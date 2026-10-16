// libyuv stub implementations: every entry point reports failure so that
// libavif's avifImageScaleWithLimit() returns an error instead of silently
// producing a corrupt image. See include/libyuv.h for details.
#include <stdint.h>

enum FilterMode {
    kFilterNone = 0,
    kFilterLinear,
    kFilterBilinear,
    kFilterBox
};

int ScalePlane(const uint8_t * src,
               int src_stride,
               int src_width,
               int src_height,
               uint8_t * dst,
               int dst_stride,
               int dst_width,
               int dst_height,
               enum FilterMode filtering)
{
    (void)src;
    (void)src_stride;
    (void)src_width;
    (void)src_height;
    (void)dst;
    (void)dst_stride;
    (void)dst_width;
    (void)dst_height;
    (void)filtering;
    return -1;
}

int ScalePlane_12(const uint16_t * src,
                  int src_stride,
                  int src_width,
                  int src_height,
                  uint16_t * dst,
                  int dst_stride,
                  int dst_width,
                  int dst_height,
                  enum FilterMode filtering)
{
    (void)src;
    (void)src_stride;
    (void)src_width;
    (void)src_height;
    (void)dst;
    (void)dst_stride;
    (void)dst_width;
    (void)dst_height;
    (void)filtering;
    return -1;
}

int ScalePlane_16(const uint16_t * src,
                  int src_stride,
                  int src_width,
                  int src_height,
                  uint16_t * dst,
                  int dst_stride,
                  int dst_width,
                  int dst_height,
                  enum FilterMode filtering)
{
    (void)src;
    (void)src_stride;
    (void)src_width;
    (void)src_height;
    (void)dst;
    (void)dst_stride;
    (void)dst_width;
    (void)dst_height;
    (void)filtering;
    return -1;
}
