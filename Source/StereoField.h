// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#ifndef _STEREO_FIELD_H_
#define _STEREO_FIELD_H_

#include <sys/types.h>

typedef struct {
    float volume;
    float width;
    float balance;
} StereoField;

extern void ApplyStereoFieldWidth(float width, float *left, float *right, size_t frameCount);
extern void ApplyStereoFieldVolumeAndBalance(float leftVolume, float rightVolume, float balance, float *left, float *right, size_t frameCount);

#endif
