// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

@import Foundation;
@class Biquad;
@class Preset;


typedef struct NoisyProgram NoisyProgram;
typedef struct NoisyNodeList NoisyNodeList;

extern NoisyProgram *NoisyProgramCreate(
    Preset *preset,
    size_t channelCount,
    double sampleRate,
    NSError **outError
);

extern void NoisyProgramFree(NoisyProgram *self);

extern void NoisyProgramProcess(NoisyProgram *self, float *left, float *right, size_t frameCount);

extern void NoisyProgramGetAutoGain(NoisyProgram *self, float *outLeft, float *outRight);

extern size_t NoisyProgramGetChannelCount(NoisyProgram *self);
