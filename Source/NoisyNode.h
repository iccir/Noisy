// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#ifndef _NOISY_NODE_H_
#define _NOISY_NODE_H_

#include <sys/types.h>
#include <stdbool.h>
#include <Accelerate/Accelerate.h>

typedef void *NoisyNodeRef;

extern void NoisyNodeFree(NoisyNodeRef self);


#pragma mark - Biquads

typedef struct NoisyBiquadsNode NoisyBiquadsNode;

extern NoisyBiquadsNode *NoisyBiquadsNodeCreate(const double *coefficients, size_t sectionCount);
extern void NoisyBiquadsNodeFree(NoisyBiquadsNode *self);
extern void NoisyBiquadsNodeProcess(NoisyBiquadsNode *self, float *buffer, size_t frameCount);


#pragma mark - DC Block

typedef struct NoisyDCBlockNode NoisyDCBlockNode;

extern NoisyDCBlockNode *NoisyDCBlockNodeCreate(void);
extern void NoisyDCBlockNodeFree(NoisyDCBlockNode *self);
extern void NoisyDCBlockNodeProcess(NoisyDCBlockNode *self, float *buffer, size_t frameCount);


#pragma mark - Gain

typedef struct NoisyGainNode NoisyGainNode;

extern NoisyGainNode *NoisyGainNodeCreate(double gain);
extern void NoisyGainNodeFree(NoisyGainNode *self);
extern void NoisyGainNodeProcess(NoisyGainNode *self, float *buffer, size_t frameCount);


#pragma mark - Generator

typedef enum NoisyGeneratorType {
    NoisyGeneratorTypeUniform,
    NoisyGeneratorTypeGaussian,
    NoisyGeneratorTypeBrownian
} NoisyGeneratorType;

typedef struct NoisyGeneratorNode NoisyGeneratorNode;

extern NoisyGeneratorNode *NoisyGeneratorNodeCreate(NoisyGeneratorType type, uint64_t randomSeed);
extern void NoisyGeneratorNodeFree(NoisyGeneratorNode *self);
extern void NoisyGeneratorNodeProcess(NoisyGeneratorNode *self, float *buffer, size_t frameCount);


#pragma mark - Node List

typedef struct NoisyNodeList NoisyNodeList;

extern NoisyNodeList *NoisyNodeListCreate(size_t capacity);
extern void NoisyNodeListFree(NoisyNodeList *self);
extern void NoisyNodeListAppend(NoisyNodeList *self, NoisyNodeRef node);
extern void NoisyNodeListProcess(NoisyNodeList *self, float *buffer, size_t frameCount);


#pragma mark - OnePole

typedef struct NoisyOnePoleNode NoisyOnePoleNode;

extern NoisyOnePoleNode *NoisyOnePoleNodeCreate(double Fc, bool isHighpass);
extern void NoisyOnePoleNodeFree(NoisyOnePoleNode *self);
extern void NoisyOnePoleNodeProcess(NoisyOnePoleNode *self, float *buffer, size_t frameCount);


#pragma mark - Pinking

typedef enum NoisyPinkingType {
    NoisyPinkingTypePK3,
    NoisyPinkingTypePKE,
    NoisyPinkingTypeRBJ
} NoisyPinkingType;

typedef struct NoisyPinkingNode NoisyPinkingNode;

extern NoisyPinkingNode *NoisyPinkingNodeCreate(NoisyPinkingType type);
extern void NoisyPinkingNodeFree(NoisyPinkingNode *self);
extern void NoisyPinkingNodeProcess(NoisyPinkingNode *self, float *buffer, size_t frameCount);


#pragma mark - Split

typedef struct NoisySplitNode NoisySplitNode;

extern NoisySplitNode *NoisySplitNodeCreate(size_t capacity);
extern void NoisySplitNodeFree(NoisySplitNode *self);
extern void NoisySplitNodeProcess(NoisySplitNode *self, float *buffer, size_t frameCount);
extern void NoisySplitNodeAppendNodeList(NoisySplitNode *self, NoisyNodeList *nodeList);


#pragma mark - Zero

typedef struct NoisyZeroNode NoisyZeroNode;

extern NoisyZeroNode *NoisyZeroNodeCreate(void);
extern void NoisyZeroNodeFree(NoisyZeroNode *self);
extern void NoisyZeroNodeProcess(NoisyZeroNode *self, float *buffer, size_t frameCount);


#endif
