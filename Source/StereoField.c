// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#include "StereoField.h"

#include <stdlib.h>
#include <math.h>
#include <Accelerate/Accelerate.h>


void ApplyStereoFieldWidth(float width, float *left, float *right, size_t frameCount)
{
    if (width < -1.0f) width   = -1.0f;
    if (width >  1.0f) width   =  1.0f;

    if (width != 1.0) {
        const float myWidth    = (width + 1.0f) *  0.5f;
        const float otherWidth = (width - 1.0f) * -0.5f;

        for (size_t i = 0; i < frameCount; i++) {
            const float l = left[i];
            const float r = right[i];

            left[i]  = (l * myWidth) + (r * otherWidth);
            right[i] = (r * myWidth) + (l * otherWidth);
        }
    }
}


void ApplyStereoFieldVolumeAndBalance(float leftVolume, float rightVolume, float balance, float *left, float *right, size_t frameCount)
{
    if (balance < -1.0f) balance = -1.0f;
    if (balance >  1.0f) balance =  1.0f;

    float leftMultiplier  = (1.0 - balance);
    float rightMultiplier = (1.0 + balance);

    if (leftMultiplier > 1.0)  leftMultiplier  = 1.0;
    if (rightMultiplier > 1.0) rightMultiplier = 1.0;
    
    leftMultiplier  *= leftVolume;
    rightMultiplier *= rightVolume;

    if (left)  vDSP_vsmul(left,  1, &leftMultiplier,  left,  1, frameCount);
    if (right) vDSP_vsmul(right, 1, &rightMultiplier, right, 1, frameCount);
}
