// (c) 2019-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "Biquad.h"

@import Accelerate;

@implementation Biquad

#pragma mark - Class Methods

/*
    Implements the standard "Cookbook formulae" from Audio-EQ-Cookbook.txt
    by Robert Bristow-Johnson
*/
+ (void) fillCoefficients: (double *) coefficients
              biquadArray: (NSArray<Biquad *> *) biquadArray
               sampleRate: (double) sampleRate
{
    vDSP_Length biquadCount = [biquadArray count];
    if (!biquadCount) return;

    NSInteger c = 0;

    for (Biquad *biquad in biquadArray) {
        BiquadType type = [biquad type];

        double b0 = 0;
        double b1 = 0;
        double b2 = 0;
        double a0 = 0;
        double a1 = 0;
        double a2 = 0;

        double A      = pow(10, [biquad gain] / 40.0);
        double w0     = 2 * M_PI * ([biquad frequency] / sampleRate);
        double sin_w0 = sin(w0);
        double cos_w0 = cos(w0);
        double alpha  = sin_w0 / (2 * [biquad Q]);

        if (type == BiquadTypeLowpass) {
            b0 =  (1.0 - cos_w0) / 2.0;
            b1 =   1.0 - cos_w0;
            b2 =  (1.0 - cos_w0) / 2.0;
            a0 =   1.0 + alpha;
            a1 =  -2.0 * cos_w0;
            a2 =   1.0 - alpha;

        } else if (type == BiquadTypeHighpass) {
            b0 =  (1.0 + cos_w0) / 2.0;
            b1 = -(1.0 + cos_w0);
            b2 =  (1.0 + cos_w0) / 2.0;
            a0 =   1.0 + alpha;
            a1 =  -2.0 * cos_w0;
            a2 =   1.0 - alpha;

        } else if (type == BiquadTypeBandpass) {
            b0 =   alpha;
            b1 =   0.0;
            b2 =  -alpha;
            a0 =   1.0 + alpha;
            a1 =  -2.0 * cos_w0;
            a2 =   1.0 - alpha;

        } else if (type == BiquadTypeNotch) {
            b0 =   1.0;
            b1 =  -2.0 * cos_w0;
            b2 =   1.0;
            a0 =   1.0 + alpha;
            a1 =  -2.0 * cos_w0;
            a2 =   1.0 - alpha;

        } else if (type == BiquadTypeLowshelf || type == BiquadTypeHighshelf) {
            double Aplus1      = A + 1.0;
            double Aminus1     = A - 1.0;
            double Aplus1_cos  = Aplus1  * cos_w0;
            double Aminus1_cos = Aminus1 * cos_w0;
            double beta_sin    = sqrt(A) * M_SQRT2 * sin_w0;

            if (type == BiquadTypeLowshelf) {
                b0 =        A * ( Aplus1  - Aminus1_cos + beta_sin );
                b1 =  2.0 * A * ( Aminus1 - Aplus1_cos             );
                b2 =        A * ( Aplus1  - Aminus1_cos - beta_sin );
                a0 =            ( Aplus1  + Aminus1_cos + beta_sin );
                a1 = -2.0     * ( Aminus1 + Aplus1_cos             );
                a2 =            ( Aplus1  + Aminus1_cos - beta_sin );
            } else {
                b0 =        A * ( Aplus1  + Aminus1_cos + beta_sin );
                b1 = -2.0 * A * ( Aminus1 + Aplus1_cos             );
                b2 =        A * ( Aplus1  + Aminus1_cos - beta_sin );
                a0 =            ( Aplus1  - Aminus1_cos + beta_sin );
                a1 =  2.0     * ( Aminus1 - Aplus1_cos             );
                a2 =            ( Aplus1  - Aminus1_cos - beta_sin );
            }

        } else if (type == BiquadTypePeaking) {
            b0 =   1.0 + alpha * A;
            b1 =  -2.0 * cos_w0;
            b2 =   1.0 - alpha * A;
            a0 =   1.0 + alpha / A;
            a1 =  -2.0 * cos_w0;
            a2 =   1.0 - alpha / A;
        }

        coefficients[c++] = b0 / a0;
        coefficients[c++] = b1 / a0;
        coefficients[c++] = b2 / a0;
        coefficients[c++] = a1 / a0;
        coefficients[c++] = a2 / a0;
    }
}


- (instancetype) initWithType: (BiquadType) type
                    frequency: (double) frequency
                            Q: (double) Q
                         gain: (double) gain
{
    if ((self = [super init])) {
        _type = type;
        _frequency = frequency;
        _Q = Q;
        _gain = gain;
    }
    
    return self;
}


@end

