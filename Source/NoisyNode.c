// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#include "NoisyNode.h"

#include <stdlib.h>
#include <math.h>
#include <Accelerate/Accelerate.h>


typedef struct NoisyNodeVTable {
    void (*process)(void *self, float *buffer, size_t frameCount);
    void (*free)(void *self);
} NoisyNodeVTable;


#define AllocSelf( __NODE__ ) \
    __NODE__ *self = calloc(1, sizeof( __NODE__ )); \
    self->vtable.process = (void *) __NODE__ ## Process; \
    self->vtable.free    = (void *) __NODE__ ## Free;


static void sProcess(NoisyNodeRef self, float *buffer, size_t frameCount)
{
    ((NoisyNodeVTable *)self)->process(self, buffer, frameCount);
}


void NoisyNodeFree(NoisyNodeRef self)
{
    if (self) {
        ((NoisyNodeVTable *)self)->free(self);
    }
}


#pragma mark - Biquads

typedef struct NoisyBiquadsNode {
    NoisyNodeVTable vtable;
    vDSP_biquad_Setup setup;
    float *delay;
} NoisyBiquadsNode;


NoisyBiquadsNode *NoisyBiquadsNodeCreate(const double *coefficients, size_t sectionCount)
{
    AllocSelf(NoisyBiquadsNode);
  
    // Per vDSP_biquad() documentation:
    // "The length of the array should be (2 * M) + 2, where M is the number of sections."
    size_t delayCount = (2 * sectionCount) + 2;
    
    self->setup = sectionCount > 0 ? vDSP_biquad_CreateSetup(coefficients, sectionCount) : NULL;
    self->delay = calloc(delayCount, sizeof(float));
    
    return self;
}


void NoisyBiquadsNodeFree(NoisyBiquadsNode *self)
{
    if (self->setup) {
        vDSP_biquad_DestroySetup(self->setup);
    }
    
    free(self->delay);
    
    free(self);
}


void NoisyBiquadsNodeProcess(NoisyBiquadsNode *self, float *buffer, size_t frameCount)
{
    if (self->setup) {
        vDSP_biquad(self->setup, self->delay, buffer, 1, buffer, 1, frameCount);
    }
}


#pragma mark - DCBlock

typedef struct NoisyDCBlockNode {
    NoisyNodeVTable vtable;
    float x1, y1;
} NoisyDCBlockNode;


NoisyDCBlockNode *NoisyDCBlockNodeCreate(void)
{
    AllocSelf(NoisyDCBlockNode);
    return self;
}


void NoisyDCBlockNodeFree(NoisyDCBlockNode *self)
{
    free(self);
}


void NoisyDCBlockNodeProcess(NoisyDCBlockNode *self, float *buffer, size_t frameCount)
{
    float x1 = self->x1;
    float y1 = self->y1;

    for (size_t i = 0; i < frameCount; i++) {
        float x0 = buffer[i];
		y1 = buffer[i] = x0 - x1 + 0.9997 * y1;
		x1 = x0;
	}
 
    self->x1 = x1;
    self->y1 = y1;
}


#pragma mark - Gain

typedef struct NoisyGainNode {
    NoisyNodeVTable vtable;
    float scalar;
} NoisyGainNode;


extern NoisyGainNode *NoisyGainNodeCreate(double gain)
{
    AllocSelf(NoisyGainNode);
    
    self->scalar = pow(10.0, gain / 20.0);

    return self;
}


void NoisyGainNodeFree(NoisyGainNode *self)
{
    free(self);
}


void NoisyGainNodeProcess(NoisyGainNode *self, float *buffer, size_t frameCount)
{
    vDSP_vsmul(buffer, 1, &self->scalar, buffer, 1, frameCount);
}


#pragma mark - Generator

typedef struct NoisyGeneratorNode {
    NoisyNodeVTable vtable;
    NoisyGeneratorType type;
    uint64_t s[4];
    float z;
} NoisyGeneratorNode;


/*
    This is Sebastiano Vigna's "SplitMix64" generator, as recommended
    by the xoshiro256** authors to seed the initial state.
    See https://prng.di.unimi.it
*/
void sGeneratorSeedRandom(NoisyGeneratorNode *self, uint64_t seed)
{
    uint64_t x = seed;

    for (size_t i = 0; i < 4; i++) {
        uint64_t z = (x += 0x9e3779b97f4a7c15);
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
        z = (z ^ (z >> 27)) * 0x94d049bb133111eb;

        self->s[i] =  z ^ (z >> 31);
    }
}


/*
    This implements the xoshiro256** algorithm to generate a 64-bit unsigned integer.
    See https://prng.di.unimi.it for more information about xoshiro256**
*/
static uint64_t sGeneratorGetNextRandom(NoisyGeneratorNode *self)
{
    uint64_t *s = self->s;
    
    const uint64_t s1_5 = s[1] * 5;
    const uint64_t result = ((s1_5 << 7) | (s1_5 >> (64 - 7))) * 9;
    const uint64_t t = s[1] << 17;

    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];

    s[2] ^= t;

    const uint64_t s3 = s[3];
    s[3] = (s3 << 45) | (s3 >> (64 - 45));

    return result;
}


static void sGeneratorFillUniformRandom(NoisyGeneratorNode *self, float *buffer, size_t frameCount)
{
    size_t i = 0;
    size_t maskedFrameCount = frameCount & ~3;

    for (i = 0; i < maskedFrameCount; i += 4) {
        uint64_t result = sGeneratorGetNextRandom(self);

        buffer[i + 0] = (uint16_t)((result & 0xFFFF000000000000) >> 48);
        buffer[i + 1] = (uint16_t)((result & 0x0000FFFF00000000) >> 32);
        buffer[i + 2] = (uint16_t)((result & 0x00000000FFFF0000) >> 16);
        buffer[i + 3] = (uint16_t)((result & 0x000000000000FFFF)      );
    }
    
    if (i < frameCount) {
        uint64_t result = sGeneratorGetNextRandom(self);

        if (i < frameCount) buffer[i++] = (uint16_t)((result & 0xFFFF000000000000) >> 48);
        if (i < frameCount) buffer[i++] = (uint16_t)((result & 0x0000FFFF00000000) >> 32);
        if (i < frameCount) buffer[i++] = (uint16_t)((result & 0x00000000FFFF0000) >> 16);
    }

    float scale = 2.0f / (float)(UINT16_MAX);
    float minusOne = -1.0f;

    // buffer[i] = (buffer[i] * scale) - 1.0f
    vDSP_vsmsa(buffer, 1, &scale, &minusOne, buffer, 1, frameCount);
}


static void sGeneratorFillGaussianRandom(NoisyGeneratorNode *self, float *buffer, size_t frameCount)
{
    for (size_t i = 0; i < frameCount; i++) {
        uint64_t result = sGeneratorGetNextRandom(self);
        
        buffer[i] = (
            (uint16_t)((result & 0xFFFF000000000000) >> 48) +
            (uint16_t)((result & 0x0000FFFF00000000) >> 32) +
            (uint16_t)((result & 0x00000000FFFF0000) >> 16) +
            (uint16_t) (result & 0x000000000000FFFF)
        );
    }

    float scale = 1.0f / (float)(UINT16_MAX * 2);
    float minusOne = -1.0f;

    // buffer[i] = (buffer[i] * scale) - 1
    vDSP_vsmsa(buffer, 1, &scale, &minusOne, buffer, 1, frameCount);
}


/*
    This is based on Douglas McCausland's "Brown Noise" Max patch
    which is based on code by Luigi Castelli.
*/
static void sApplyBrownianWalk(NoisyGeneratorNode *self, float *buffer, size_t frameCount)
{
    float z = self->z;
    
    float step = 0.01f;
    vDSP_vsmul(buffer, 1, &step, buffer, 1, frameCount);

    for (size_t i = 0; i < frameCount; i++) {
        z += buffer[i];
        
        if (z > 1.0) {
            z = 2.0 - z;
        } else if (z < -1.0) {
            z = -2.0 - z;
        }
        
        buffer[i] = z;
    }
    
    self->z = z;
}


NoisyGeneratorNode *NoisyGeneratorNodeCreate(NoisyGeneratorType type, uint64_t randomSeed)
{
    AllocSelf(NoisyGeneratorNode);
    
    self->type = type;
    sGeneratorSeedRandom(self, randomSeed);

    return self;
}


void NoisyGeneratorNodeFree(NoisyGeneratorNode *self)
{
    free(self);
}


void NoisyGeneratorNodeProcess(NoisyGeneratorNode *self, float *buffer, size_t frameCount)
{
    if (self->type == NoisyGeneratorTypeUniform) {
        sGeneratorFillUniformRandom(self, buffer, frameCount);
    
    } else if (self->type == NoisyGeneratorTypeGaussian) {
        sGeneratorFillGaussianRandom(self, buffer, frameCount);
    
    } else if (self->type == NoisyGeneratorTypeBrownian) {
        sGeneratorFillUniformRandom(self, buffer, frameCount);
        sApplyBrownianWalk(self, buffer, frameCount);
    }
}


#pragma mark - NodeList

typedef struct NoisyNodeList {
    NoisyNodeVTable vtable;
    size_t count;
    size_t capacity;
    NoisyNodeRef *nodes;
} NoisyNodeList;


NoisyNodeList *NoisyNodeListCreate(size_t capacity)
{
    AllocSelf(NoisyNodeList);
    
    self->capacity = capacity;
    self->nodes = capacity ? calloc(capacity, sizeof(NoisyNodeRef)) : NULL;
    
    return self;
}


void NoisyNodeListFree(NoisyNodeList *self)
{
    for (size_t i = 0; i < self->count; i++) {
        NoisyNodeFree(self->nodes[i]);
    }

    free(self->nodes);
    free(self);
}


void NoisyNodeListAppend(NoisyNodeList *self, NoisyNodeRef node)
{
    if (self->count < self->capacity) {
        self->nodes[self->count++] = node;
    } else {
        abort();
    }
}


void NoisyNodeListProcess(NoisyNodeList *self, float *buffer, size_t frameCount)
{
    if (self) {
        for (size_t i = 0; i < self->count; i++) {
            sProcess(self->nodes[i], buffer, frameCount);
        }
    }
}


#pragma mark - OnePole

typedef struct NoisyOnePoleNode {
    NoisyNodeVTable vtable;
    float a0, b1, y1;
} NoisyOnePoleNode;


extern NoisyOnePoleNode *NoisyOnePoleNodeCreate(double Fc, bool isHighpass)
{
    AllocSelf(NoisyOnePoleNode);
    
    float a0, b1;

    /*
        This formula is a widely-used approximation.
        See https://dsp.stackexchange.com/questions/28308
    */
    if (isHighpass) {
        b1 = -exp(-2.0 * M_PI * (0.5 - Fc));
        a0 = 1.0 + b1;
    } else {
        b1 = exp(-2.0 * M_PI * Fc);
        a0 = 1.0 - b1;
    }

    self->a0 = a0;
    self->b1 = b1;
    
    return self;
}


void NoisyOnePoleNodeFree(NoisyOnePoleNode *self)
{
    free(self);
}


void NoisyOnePoleNodeProcess(NoisyOnePoleNode *self, float *buffer, size_t frameCount)
{
    const float a0 = self->a0;
    const float b1 = self->b1;
    
    float y1 = self->y1;

    for (size_t i = 0; i < frameCount; i++) {
        buffer[i] = y1 = a0 * buffer[i] + b1 * y1;
    }
    
    self->y1 = y1;
}


#pragma mark - Pinking

typedef struct NoisyPinkingNode {
    NoisyNodeVTable vtable;
    NoisyPinkingType type;

    union {
        struct { float b0, b1, b2, b3, b4, b5, b6; } pk3;
        struct { float b0, b1, b2; } pke;
        struct { float x1, x2, x3, y1, y2, y3; } rbj;
    };
} NoisyPinkingNode;


/*
    Implements Paul Kellet's "pke" filter as posted to the Music-DSP mailing list
    on 1999-10-17. See https://www.firstpr.com.au/dsp/pink-noise/#Filtering
*/
static void sPinkingApplyPKE(NoisyPinkingNode *self, float *buffer, size_t frameCount)
{
    float b0 = self->pke.b0;
    float b1 = self->pke.b1;
    float b2 = self->pke.b2;

    for (size_t i = 0; i < frameCount; i++) {
        float white = buffer[i];

        const float gain = 0.12;

        float w0 = white * gain * 0.0990460;
        float w1 = white * gain * 0.2965164;
        float w2 = white * gain * 1.0526913;
        float w3 = white * gain * 0.1848;
        
        b0 = 0.99765 * b0 + w0;
        b1 = 0.96300 * b1 + w1;
        b2 = 0.57000 * b2 + w2;

        buffer[i] = b0 + b1 + b2 + w3;
    }

    self->pk3.b0 = b0;
    self->pk3.b1 = b1;
    self->pk3.b2 = b2;
}


/*
    Implements Paul Kellet's "pk3" filter as posted to the Music-DSP mailing list
    on 1999-10-17. See https://www.firstpr.com.au/dsp/pink-noise/#Filtering
*/
static void sPinkingApplyPK3(NoisyPinkingNode *self, float *buffer, size_t frameCount)
{
    float b0 = self->pk3.b0;
    float b1 = self->pk3.b1;
    float b2 = self->pk3.b2;
    float b3 = self->pk3.b3;
    float b4 = self->pk3.b4;
    float b5 = self->pk3.b5;
    float b6 = self->pk3.b6;

    for (size_t i = 0; i < frameCount; i++) {
        float white = buffer[i];
        
        const float gain = 0.12;

        float w0 = white * gain * 0.0555179;
        float w1 = white * gain * 0.0750759;
        float w2 = white * gain * 0.1538520;
        float w3 = white * gain * 0.3104856;
        float w4 = white * gain * 0.5329522;
        float w5 = white * gain * 0.0168980;
        float w6 = white * gain * 0.115926;
        float w7 = white * gain * 0.5362;
        
        b0 =  0.99886 * b0 + w0;
        b1 =  0.99332 * b1 + w1;
        b2 =  0.96900 * b2 + w2;
        b3 =  0.86650 * b3 + w3;
        b4 =  0.55000 * b4 + w4;
        b5 = -0.7616  * b5 - w5;

        float pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w7;
        b6 = w6;

        buffer[i] = pink;
    }

    self->pk3.b0 = b0;
    self->pk3.b1 = b1;
    self->pk3.b2 = b2;
    self->pk3.b3 = b3;
    self->pk3.b4 = b4;
    self->pk3.b5 = b5;
    self->pk3.b6 = b6;
}


/*
    Implements Robert Bristow-Johnson's 3-pole, 3-zero filter as posted to the
    Music-DSP mailing list on 1998-06-30. His pole/zero values have been converted
    into coefficients via scipy.signal.zpk2tf() with a gain of 0.2
    
    See https://www.firstpr.com.au/dsp/pink-noise/#Filtering
*/
static void sPinkingApplyRBJ(NoisyPinkingNode *self, float *buffer, size_t frameCount)
{
    float x1 = self->rbj.x1;
    float x2 = self->rbj.x2;
    float x3 = self->rbj.x3;
    float y1 = self->rbj.y1;
    float y2 = self->rbj.y2;
    float y3 = self->rbj.y3;

    for (size_t i = 0; i < frameCount; i++) {
        float x0 = buffer[i];

        float y0 = buffer[i] =
            (0.2 * x0) + (-0.37880859 * x1) + (0.19171283 * x2) + (-0.0124264  * x3)
                       - (-2.47930908 * y1) - (1.98501285 * y2) - (-0.50560043 * y3);

        x3 = x2;  x2 = x1;  x1 = x0;
        y3 = y2;  y2 = y1;  y1 = y0;
    }

    self->rbj.x1 = x1;
    self->rbj.x2 = x2;
    self->rbj.x3 = x3;

    self->rbj.y1 = y1;
    self->rbj.y2 = y2;
    self->rbj.y3 = y3;
}


NoisyPinkingNode *NoisyPinkingNodeCreate(NoisyPinkingType type)
{
    AllocSelf(NoisyPinkingNode);
    
    self->type = type;
   
    return self;
}


void NoisyPinkingNodeFree(NoisyPinkingNode *self)
{
    free(self);
}


void NoisyPinkingNodeProcess(NoisyPinkingNode *self, float *buffer, size_t frameCount)
{
    if (self->type == NoisyPinkingTypePK3) {
        sPinkingApplyPK3(self, buffer, frameCount);
    } else if (self->type == NoisyPinkingTypePKE) {
        sPinkingApplyPKE(self, buffer, frameCount);
    } else if (self->type == NoisyPinkingTypeRBJ) {
        sPinkingApplyRBJ(self, buffer, frameCount);
    }
}


#pragma mark - Split

typedef struct NoisySplitNode {
    NoisyNodeVTable vtable;

    size_t maxFrames;

    NoisyNodeList **lists;
    size_t listCapacity;
    size_t listCount;

    float **scratchBuffers;
    size_t  scratchCount;
} NoisySplitNode;


NoisySplitNode *NoisySplitNodeCreate(size_t capacity)
{
    AllocSelf(NoisySplitNode);

    size_t scratchCount = capacity > 0 ? capacity - 1 : 0;

    size_t maxFrames = 2048;
    self->maxFrames   = maxFrames;
    
    self->listCapacity = capacity;
    self->lists        = capacity > 0 ? calloc(capacity, sizeof(NoisyNodeList *)) : NULL;

    self->scratchCount   = scratchCount;
    self->scratchBuffers = scratchCount > 0 ? malloc(sizeof(float *) * scratchCount) : NULL;
    
    for (size_t i = 0; i < scratchCount; i++) {
        self->scratchBuffers[i] = malloc(sizeof(float) * maxFrames);
    }

    return self;
}


void NoisySplitNodeFree(NoisySplitNode *self)
{
    for (size_t i = 0; i < self->listCount; i++) {
        NoisyNodeFree(self->lists[i]);
    }

    for (size_t i = 0; i < self->scratchCount; i++) {
        free(self->scratchBuffers[i]);
    }

    free(self->lists);
    free(self->scratchBuffers);

    free(self);
}


static void sSplitNodeProcess(NoisySplitNode *self, float *buffer, size_t frameCount)
{
    // Duplicate input buffer into our scratch buffers
    for (size_t i = 0; i < self->scratchCount; i++) {
        memcpy(self->scratchBuffers[i], buffer, frameCount * sizeof(float));
    }

    // Process first buffer
    if (self->listCount > 0) {
        sProcess(self->lists[0], buffer, frameCount);
    }
    
    // Process scratch buffers and sum them to output
    for (size_t i = 1; i < self->listCount; i++) {
        float *tmp = self->scratchBuffers[i - 1];
        sProcess(self->lists[i], tmp, frameCount);
        vDSP_vadd(buffer, 1, tmp, 1, buffer, 1, frameCount);
    }
}


void NoisySplitNodeProcess(NoisySplitNode *self, float *buffer, size_t inFrameCount)
{
    size_t framesRemaining = inFrameCount;
    
    while (framesRemaining > 0) {
        size_t framesToProcess = MIN(framesRemaining, self->maxFrames);

        sSplitNodeProcess(self, buffer, framesToProcess);

        buffer += framesToProcess;
        framesRemaining -= framesToProcess;
    }
}


void NoisySplitNodeAppendNodeList(NoisySplitNode *self, NoisyNodeList *nodeList)
{
    if (self->listCount < self->listCapacity) {
        self->lists[self->listCount++] = nodeList;
    } else {
        abort();
    }
}


#pragma mark - Zero

typedef struct NoisyZeroNode {
    NoisyNodeVTable vtable;
} NoisyZeroNode;


NoisyZeroNode *NoisyZeroNodeCreate(void)
{
    AllocSelf(NoisyZeroNode);
    return self;
}


void NoisyZeroNodeFree(NoisyZeroNode *self)
{
    free(self);
}


void NoisyZeroNodeProcess(NoisyZeroNode *self, float *buffer, size_t frameCount)
{
    memset(buffer, 0, sizeof(float) * frameCount);
}
