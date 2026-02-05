// (c) 2019-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

@import Foundation;

typedef NS_ENUM(NSInteger, BiquadType) {
    BiquadTypePeaking,
    BiquadTypeLowpass,
    BiquadTypeHighpass,
    BiquadTypeBandpass,
    BiquadTypeNotch,
    BiquadTypeLowshelf,
    BiquadTypeHighshelf
};

@interface Biquad : NSObject

+ (void) fillCoefficients: (double *) coefficients
              biquadArray: (NSArray<Biquad *> *) biquadArray
               sampleRate: (double) sampleRate;

- (instancetype) initWithType: (BiquadType) type
                    frequency: (double) frequency
                            Q: (double) Q
                         gain: (double) gain;

@property (nonatomic, readonly) BiquadType type;
@property (nonatomic, readonly) double frequency;
@property (nonatomic, readonly) double Q;
@property (nonatomic, readonly) double gain;

@end

