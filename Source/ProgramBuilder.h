// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

@import Foundation;

@class Preset;
typedef struct NoisyProgram  NoisyProgram;
typedef struct NoisyNodeList NoisyNodeList;

extern NSErrorDomain ProgramBuilderErrorDomain;

@interface ProgramBuilder : NSObject

- (instancetype) initWithPreset: (Preset *) preset
                   channelCount: (size_t) channelCount
                     sampleRate: (double) sampleRate
                    forAutoGain: (BOOL) forAutoGain;

// Input properties
@property (nonatomic, readonly) Preset *preset;
@property (nonatomic, readonly) size_t channelCount;
@property (nonatomic, readonly) double sampleRate;
@property (nonatomic, readonly) BOOL forAutoGain;


// Output properties

- (void) transferHeadNodeList: (NoisyNodeList **) outHeadNodeList
                 leftNodeList: (NoisyNodeList **) outLeftNodeList
                rightNodeList: (NoisyNodeList **) outRightNodeList;

@property (nonatomic, readonly) NSError *error;

@property (nonatomic, readonly) double autoGainLevel;
@property (nonatomic, readonly) size_t autoGainSampleCount;
@property (nonatomic, readonly, getter=isAutoGainSeparate) BOOL autoGainSeparate;

@end

