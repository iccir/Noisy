// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "NoisyProgram.h"

#import "Biquad.h"
#import "Preset.h"
#import "NoisyNode.h"
#import "ProgramBuilder.h"

@import Accelerate;



typedef struct NoisyProgram {
    size_t channelCount;
    double sampleRate;

    float autoGainLevel;
    BOOL  isAutoGainSeparate;
    float leftAutoGain;
    float rightAutoGain;

    NoisyNodeList *headNodeList;
    NoisyNodeList *leftNodeList;
    NoisyNodeList *rightNodeList;
} NoisyProgram;


#pragma mark - Private Functions



static NoisyProgram *sCreateProgram(ProgramBuilder *builder)
{
    NoisyProgram *self = calloc(1, sizeof(NoisyProgram));

    self->channelCount  = [builder channelCount];
    self->sampleRate    = [builder sampleRate];
    
    [builder transferHeadNodeList: &self->headNodeList
                     leftNodeList: &self->leftNodeList
                    rightNodeList: &self->rightNodeList];

    return self;
}


static void sComputeAutoGain(ProgramBuilder *builder, float *outLeft, float *outRight)
{
    NoisyProgram *program = sCreateProgram(builder);

    double targetLevel = [builder autoGainLevel];

    // Approximately 6 seconds of audio at 44.1Khz
    size_t samplesToGenerate = 256 * 1024;

    float *left   = malloc(sizeof(float) * samplesToGenerate);
    float *right  = malloc(sizeof(float) * samplesToGenerate);

    NoisyProgramProcess(program, left, right, samplesToGenerate);
    
    float leftMinValue, leftMaxValue;
    vDSP_minv(left,  1, &leftMinValue,  samplesToGenerate);
    vDSP_maxv(left,  1, &leftMaxValue,  samplesToGenerate);
    if (-leftMinValue > leftMaxValue) leftMaxValue = -leftMinValue;

    float rightMinValue, rightMaxValue;
    vDSP_minv(right, 1, &rightMinValue, samplesToGenerate);
    vDSP_maxv(right, 1, &rightMaxValue, samplesToGenerate);
    if (-rightMinValue > rightMaxValue) rightMaxValue = -rightMinValue;

    free(left);
    free(right);
    NoisyProgramFree(program);

    double targetValue = pow(10.0, targetLevel / 20.0);
    

    if ([builder isAutoGainSeparate]) {
        NSLog(@"Auto gain left max value:  %lf dBFS", (double)(20.0 * log10(leftMaxValue)));
        NSLog(@"Auto gain right max value: %lf dBFS", (double)(20.0 * log10(rightMaxValue)));
        
        *outLeft  = targetValue / leftMaxValue;
        *outRight = targetValue / rightMaxValue;
    } else {
        float maxValue = MAX(leftMaxValue, rightMaxValue);

        NSLog(@"Auto gain max value: %lf dBFS", (double)(20.0 * log10(maxValue)));

        *outLeft  = targetValue / maxValue;
        *outRight = targetValue / maxValue;
    }
}


#pragma mark - Public Functions

NoisyProgram *NoisyProgramCreate(
    Preset *preset,
    size_t channelCount,
    double sampleRate,
    NSError **outError
) {
    if ([preset error]) {
        if (outError) *outError = [preset error];
        return NULL;
    }

    ProgramBuilder *selfBuilder = [[ProgramBuilder alloc] initWithPreset: preset
                                                            channelCount: channelCount
                                                              sampleRate: sampleRate
                                                             forAutoGain: NO];

    if ([selfBuilder error]) {
        if (outError) *outError = [selfBuilder error];
        return NULL;
    }

    // For Auto Gain, we always use stereo with a sample rate of 44100.0
    ProgramBuilder *autoGainBuilder = [[ProgramBuilder alloc] initWithPreset: preset
                                                                channelCount: 2
                                                                  sampleRate: 44100
                                                                 forAutoGain: YES];

    if ([autoGainBuilder error]) {
        if (outError) *outError = [autoGainBuilder error];
        return NULL;
    }

    NoisyProgram *self = sCreateProgram(selfBuilder);

    sComputeAutoGain(autoGainBuilder, &self->leftAutoGain, &self->rightAutoGain);

    return self;
}


void NoisyProgramFree(NoisyProgram *self)
{
    if (!self) return;

    NoisyNodeFree(self->headNodeList);
    NoisyNodeFree(self->leftNodeList);
    NoisyNodeFree(self->rightNodeList);

    free(self);
}


void NoisyProgramProcess(NoisyProgram *self, float *left, float *right, size_t frameCount)
{
    NoisyNodeListProcess(self->headNodeList, left, frameCount);

    memcpy(right, left, sizeof(float) * frameCount);

    NoisyNodeListProcess(self->leftNodeList, left, frameCount);
    NoisyNodeListProcess(self->rightNodeList, right, frameCount);
}

void NoisyProgramGetAutoGain(NoisyProgram *self, float *outLeft, float *outRight)
{
    *outLeft  = self->leftAutoGain;
    *outRight = self->rightAutoGain;
}


extern size_t NoisyProgramGetChannelCount(NoisyProgram *self)
{
    return self->channelCount;
}

