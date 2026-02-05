// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#include "Ramper.h"

#include <Accelerate/Accelerate.h>
#include <stdlib.h>
#include <math.h>
#include <stdatomic.h>


static const size_t sMaxFramesToProcess = 512;


typedef struct Ramper {
    float currentVolume;
    float targetVolume;
    
    float rampStep;
    int remainingFrames;
    int totalFrames;
    
    float scratch[sMaxFramesToProcess];

    _Atomic(int) currentData;
    _Atomic(int) nextData;
} Ramper;


Ramper *RamperCreate(void)
{
    Ramper *self = calloc(1, sizeof(Ramper));
    RamperReset(self);
    return self;
}


extern void RamperFree(Ramper *self)
{
    free(self);
}


static void sProcess(Ramper *self, float *left, float *right, size_t offset, size_t frameCount)
{
    if (self->targetVolume == 1.0 && self->currentVolume == 1.0) {
        return; // Nothing to do.

    } else if (self->targetVolume == 0.0 && self->currentVolume == 0.0) {
        if (left)  vDSP_vclr(left  + offset, 1, frameCount);
        if (right) vDSP_vclr(right + offset, 1, frameCount);

        return;

    } else {
        float *scratch = self->scratch;

        vDSP_vramp(&self->currentVolume, &self->rampStep, scratch, 1, frameCount);

        // Apply pow(x, 4) volume curve
        vDSP_vsq(scratch, 1, scratch, 1, frameCount);
        vDSP_vsq(scratch, 1, scratch, 1, frameCount);

        if (left)  vDSP_vmul(left  + offset, 1, scratch, 1, left  + offset, 1, frameCount);
        if (right) vDSP_vmul(right + offset, 1, scratch, 1, right + offset, 1, frameCount);

        self->remainingFrames -= frameCount;

        self->currentVolume = self->currentVolume + (self->rampStep * frameCount);
        
        if (self->remainingFrames <= 0) {
            self->currentVolume = self->targetVolume;
        }
    }
}


extern void RamperProcess(Ramper *self, float *left, float *right, size_t frameCount)
{
    int currentData = atomic_load(&self->currentData);
    int nextData    = atomic_load(&self->nextData);
    
    if (currentData != nextData) {
        atomic_store(&self->currentData, nextData);
        currentData = nextData;
        
        int totalFrames = (currentData & ~1);
        
        self->targetVolume = (currentData &  1) ? 1.0 : 0.0;
        
        self->rampStep = (self->targetVolume - self->currentVolume) / totalFrames;
        
        self->totalFrames     = totalFrames;
        self->remainingFrames = totalFrames;
    }
    
    size_t frameOffset = 0;
    
    while ((frameCount > 0) && (self->remainingFrames > 0)) {
        size_t framesToProcess = frameCount;
        framesToProcess = MIN(framesToProcess, sMaxFramesToProcess);
        framesToProcess = MIN(framesToProcess, self->remainingFrames);
        
        sProcess(self, left, right, frameOffset, framesToProcess);
        
        frameOffset += framesToProcess;
        frameCount  -= framesToProcess;
    }
    
    if (frameCount > 0) {
        sProcess(self, left, right, frameOffset, frameCount);
    }
}


void RamperReset(Ramper *self)
{
    memset(self, 0, sizeof(Ramper));
}


extern void RamperUpdate(Ramper *self, int shouldPlay, size_t frameDuration)
{
    int rampData = (int)((frameDuration & ~0x1) | (shouldPlay ? 0x1 : 0x0));
    atomic_store(&self->nextData, rampData);
}

