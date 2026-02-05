// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "AudioPlayer.h"

#import "AppDelegate.h"
#import "Biquad.h"
#import "NoisyProgram.h"
#import "Preset.h"
#import "Ramper.h"
#import "StereoField.h"
#import "Utils.h"
#import "Settings.h"

#include <stdatomic.h>

@import AVFAudio;
@import CoreAudio.AudioHardware;
@import AppKit;

static NSTimeInterval sTerminateTime = 0.05;

typedef struct {
    volatile float volume;
    volatile float stereoWidth;
    volatile float stereoBalance;
    
    volatile int muted;
    
    _Atomic(NoisyProgram *) program;
    _Atomic(NoisyProgram *) nextProgram;
    
    Ramper *ramper;
} RenderData;


NSString * const AudioPlayerDidUpdateNotificationName = @"AudioPlayerDidUpdateNotification";

@interface AudioPlayer ()
@property (nonatomic, getter=isPlaying) BOOL playing;
@property (nonatomic) NSError *error;
@end


@implementation AudioPlayer {
    RenderData _renderData;
    AVAudioSourceNode *_sourceNode;
    AVAudioEngine *_audioEngine;
    
    BOOL _terminating;
    double _activeSampleRate;
    NSError *_error;
    
    NSTimeInterval _programModifiedTimeInterval;
    
    AudioUnit _outputAudioUnit;
}


+ (instancetype) sharedInstance
{
    static AudioPlayer *sSharedInstance = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sSharedInstance = [[AudioPlayer alloc] init];
    });
    
    return sSharedInstance;
}


- (instancetype) init
{
    if ((self = [super init])) {
        _renderData.ramper = RamperCreate();

        // Restore persisted settings
        Settings *settings = [Settings sharedInstance];
        
        [self setVolume:[settings volume]];
        [self setStereoWidth:[settings stereoWidth]];
        [self setStereoBalance:[settings stereoBalance]];

        [self _setupDefaultOutputDeviceListener];
        [self _remakeOutputUnit];
        
        if ([settings rememberPlaybackState] && [settings playbackWasPlaying]) {
            [self play];
        }
    }
    
    return self;
}


#pragma mark - Private Methods

static OSStatus sRender(
    void *inRefCon,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData
) {
    RenderData *renderData = (RenderData *)inRefCon;

    NoisyProgram *program     = atomic_load(&renderData->program);
    NoisyProgram *nextProgram = atomic_load(&renderData->nextProgram);

    if (program != nextProgram) {
        atomic_store(&renderData->program, nextProgram);
        program = nextProgram;
    }

    float *left  = ioData->mBuffers[0].mData;
    float *right = ioData->mBuffers[1].mData;

    if (!program) {
        memset(left,  0, sizeof(float) * inNumberFrames);
        memset(right, 0, sizeof(float) * inNumberFrames);

        return noErr;
    }

    NoisyProgramProcess(program, left, right, inNumberFrames);

    if (NoisyProgramGetChannelCount(program) == 1) {
        RamperProcess(renderData->ramper, left, NULL, inNumberFrames);
        memcpy(right, left, sizeof(float) * inNumberFrames);

    } else {
        RamperProcess(renderData->ramper, left, right, inNumberFrames);
        ApplyStereoFieldWidth(renderData->stereoWidth, left, right, inNumberFrames);
    }

    float leftAutoGain;
    float rightAutoGain;
    NoisyProgramGetAutoGain(program, &leftAutoGain, &rightAutoGain);

    float leftVolume    = renderData->volume * leftAutoGain;
    float rightVolume   = renderData->volume * rightAutoGain;
    float stereoBalance = renderData->stereoBalance;

    ApplyStereoFieldVolumeAndBalance(leftVolume, rightVolume, stereoBalance, left, right, inNumberFrames);

    return noErr;
}


static OSStatus sHandleDefaultDeviceChanged(
    AudioObjectID inObjectID,
    UInt32 inNumberAddresses,
    const AudioObjectPropertyAddress inAddresses[],
    void *inClientData
) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[AudioPlayer sharedInstance] _remakeOutputUnit];
    });

    return noErr;
}


static void sHandleStreamFormatChanged(
    void *inRefCon,
    AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement
) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[AudioPlayer sharedInstance] _reconfigureOutputUnit];
    });
}


- (void) _setupDefaultOutputDeviceListener
{
    AudioObjectPropertyAddress defaultOutputDeviceAddress = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    CheckError(
        AudioObjectAddPropertyListener(
            kAudioObjectSystemObject,
            &defaultOutputDeviceAddress,
            sHandleDefaultDeviceChanged,
            (__bridge void *) self
        ),
        @"AudioObjectAddPropertyListener[ Default Output ]"
    );
}


- (void) _remakeOutputUnit
{
    if (_outputAudioUnit) {
        AudioUnitRemovePropertyListenerWithUserData(
            _outputAudioUnit,
            kAudioUnitProperty_StreamFormat,
            sHandleStreamFormatChanged,
            (__bridge void *) self
        );
        
        [self _reallyStopOutput];

        CheckError(
            AudioUnitUninitialize(_outputAudioUnit),
            @"AudioUnitUninitialize"
        );

        CheckError(
            AudioComponentInstanceDispose(_outputAudioUnit),
            @"AudioComponentInstanceDispose"
        );
    }

    AudioComponentDescription outputCD = {
        kAudioUnitType_Output,
        kAudioUnitSubType_HALOutput,
        kAudioUnitManufacturer_Apple,
        0,
        0
    };

    AudioComponent outputComponent = AudioComponentFindNext(NULL, &outputCD);

    CheckError(
        AudioComponentInstanceNew(outputComponent, &_outputAudioUnit),
        @"AudioComponentInstanceNew[ Output ]"
    );

    CheckError(
        AudioUnitAddPropertyListener(
            _outputAudioUnit,
            kAudioUnitProperty_StreamFormat,
            sHandleStreamFormatChanged,
            (__bridge void *) self
        ),
        @"AudioUnitAddPropertyListener[ Stream Format ]"
    );

    AURenderCallbackStruct renderCallback = { &sRender, &_renderData };

    CheckError(
        AudioUnitSetProperty(
            _outputAudioUnit,
            kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0,
            &renderCallback,
            sizeof(renderCallback)
        ),
        @"AudioUnitSetProperty[ SetRenderCallback ]"
    );

    [self _reconfigureOutputUnit];
}


- (void) _reconfigureOutputUnit
{
    UInt32 dataSize;
    BOOL ok = YES;

    BOOL wasRunning = [self _isRunning];
    if (wasRunning) {
        [self _reallyStopOutput];
    }

    ok = ok && CheckError(
        AudioUnitUninitialize(_outputAudioUnit),
        @"AudioUnitUninitialize"
    );

    double sampleRate = 0;
    
    AudioStreamBasicDescription outputFormat = {0};
    
    dataSize = sizeof(sampleRate);
    ok = ok && CheckError(
        AudioUnitGetProperty(
            _outputAudioUnit,
            kAudioUnitProperty_SampleRate,
            kAudioUnitScope_Output, 0,
            &sampleRate, &dataSize
        ),
        @"AudioUnitGetProperty[ Output Sample Rate ]"
    );
    
    dataSize = sizeof(outputFormat);
    ok = ok && CheckError(
        AudioUnitGetProperty(
            _outputAudioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output, 0,
            &outputFormat, &dataSize
        ),
        @"AudioUnitGetProperty[ Output Stream Format ]"
    );

    AudioStreamBasicDescription inputFormat = {0};

    inputFormat.mFormatID         = kAudioFormatLinearPCM;
    inputFormat.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved;
    inputFormat.mSampleRate       = outputFormat.mSampleRate;
    inputFormat.mFramesPerPacket  = 1;
    inputFormat.mBitsPerChannel   = sizeof(float) * 8;
    inputFormat.mBytesPerPacket   = sizeof(float);
    inputFormat.mChannelsPerFrame = 2;
    inputFormat.mBytesPerFrame    = (inputFormat.mFramesPerPacket * inputFormat.mBytesPerPacket);

    ok = ok && CheckError(
        AudioUnitSetProperty(
            _outputAudioUnit,
            kAudioUnitProperty_SampleRate,
            kAudioUnitScope_Input, 0,
            &sampleRate, sizeof(sampleRate)
        ),
        @"AudioUnitSetProperty[ Input Sample Rate ]"
    );

    ok = ok && CheckError(
        AudioUnitSetProperty(
            _outputAudioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input, 0,
            &inputFormat, sizeof(inputFormat)
        ),
        @"AudioUnitGetProperty[ Input Stream Format ]"
    );

    ok = ok && CheckError(
        AudioUnitInitialize(_outputAudioUnit),
        @"AudioUnitInitialize"
    );
    
    _activeSampleRate = sampleRate;
    [self _remakeProgram];

    if (wasRunning) {
        [self _reallyStartOutput];
    }
}


- (BOOL) _isRunning
{
    if (!_outputAudioUnit) return NO;

    Boolean isRunning = false;
    UInt32 size = sizeof(isRunning);

    CheckError(
        AudioUnitGetProperty(_outputAudioUnit, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0, &isRunning, &size),
        @"AudioUnitGetProperty[ Output, IsRunning ]"
    );
    
    return isRunning ? YES : NO;
}


- (void) _reallyStopOutput
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_reallyStopOutput) object:nil];
    CheckError(AudioOutputUnitStop(_outputAudioUnit), @"AudioOutputUnitStop");
}


- (void) _reallyStartOutput
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_reallyStopOutput) object:nil];
    CheckError(AudioOutputUnitStart(_outputAudioUnit), @"AudioOutputUnitStart");
}


- (void) _remakeProgram
{
    NSError *error = nil;

    NoisyProgram *newProgram = _preset ?
        NoisyProgramCreate(_preset, _stereoWidth > 0 ? 2 : 1, _activeSampleRate, &error) :
        NULL;

    NoisyProgram *previousProgram = atomic_load(&_renderData.program);
    atomic_store(&_renderData.nextProgram, newProgram);

    BOOL needsRestart = NO;

    // Wait for sRender() to move nextBiquadSetup to biquadSetup
    NSInteger loopGuard = 0;
    while ([self _isRunning]) {
        if (newProgram == atomic_load(&_renderData.program)) {
            break;
        }

        if (loopGuard >= 1000) {
            // Something is wrong
            needsRestart = YES;
            [_audioEngine stop];
            break;
        }

        usleep(1000);
        loopGuard++;
    }
    
    // If we are no longer running, store directly into generator
    if (![self _isRunning]) {
        atomic_store(&_renderData.program, newProgram);
    }

    _programModifiedTimeInterval = [[_preset modificationDate] timeIntervalSinceReferenceDate];
    [self setError:error];

    if (needsRestart && !error) {
        [self play];
    }

    if (previousProgram) {
        NoisyProgramFree(previousProgram);
    }
}


- (void) _postNotificationName:(NSString *)name
{
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self];
}


- (void) _startOrStopOutputWithFadeDuration:(NSTimeInterval)fadeDuration
{
    BOOL shouldBeRunning = _playing && !_muted && !_terminating;
    BOOL isRunning = [self _isRunning];

    size_t frameDuration = lround(fadeDuration * _activeSampleRate);

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_reallyStopOutput) object:nil];

    if (shouldBeRunning && !isRunning) {

        RamperReset(_renderData.ramper);
        RamperUpdate(_renderData.ramper, YES, frameDuration);

        [self _reallyStartOutput];

    } else if (!shouldBeRunning && isRunning) {
        RamperUpdate(_renderData.ramper, NO, frameDuration);
        [self performSelector:@selector(_reallyStopOutput) withObject:nil afterDelay:fadeDuration + 0.1];

    } else {
        RamperUpdate(_renderData.ramper, shouldBeRunning, frameDuration);
    }
}


- (void) _stepVolume:(NSInteger)direction
{
    NSInteger volumeAsInt = lround([self volume] * 16) + direction;
    
    if (volumeAsInt > 16) volumeAsInt = 16;
    if (volumeAsInt < 0)  volumeAsInt = 0;
    
    [self setVolume:(volumeAsInt / 16.0)];
}


#pragma mark - Public Methods

- (void) checkPresetModificationDate
{
    NSTimeInterval presetInterval = [[_preset modificationDate] timeIntervalSinceReferenceDate];
    
    if (_programModifiedTimeInterval < presetInterval) {
        [self _remakeProgram];
    }
}


- (void) performPlaybackAction
{
    if (_error) {
        [(AppDelegate *)[NSApp delegate] showProgramError:_error];
    } else if (![self isPlaying]) {
        [self setPlaying:YES];
    } else {
        [self setPlaying:NO];
    }
}


- (void) play
{
    if (!_error) [self setPlaying:YES];
}


- (void) pause
{
    [self setPlaying:NO];
}


- (void) increaseVolume
{
    [self _stepVolume:1];
}


- (void) decreaseVolume
{
    [self _stepVolume:-1];
}


#pragma mark - Accessors

- (void) setPreset:(Preset *)preset
{
    if (_preset != preset) {
        _preset = preset;
        [self _remakeProgram];
    }
}


- (void) setVolume:(double)volume
{
    if (_volume != volume) {
        _volume = volume;
        _renderData.volume = (volume * volume * volume);

        [[Settings sharedInstance] setVolume:volume];
    }
}


- (void) setStereoWidth:(double)stereoWidth
{
    if (_stereoWidth != stereoWidth) {
        BOOL wasStereo = _stereoWidth > 0.0;
        BOOL isStereo  =  stereoWidth > 0.0;

        _stereoWidth = stereoWidth;
        _renderData.stereoWidth = stereoWidth;

        if (wasStereo != isStereo) {
            [self _remakeProgram];
        }

        [[Settings sharedInstance] setStereoWidth:stereoWidth];
    }
}


- (void) setStereoBalance:(double)stereoBalance
{
    if (_stereoBalance != stereoBalance) {
        _stereoBalance = stereoBalance;
        _renderData.stereoBalance = stereoBalance;

        [[Settings sharedInstance] setStereoBalance:stereoBalance];
    }
}


- (void) setError:(NSError *)error
{
    if (_error != error) {
        _error = error;
        [self _postNotificationName:AudioPlayerDidUpdateNotificationName];

        if ([self isPlaying]) {
            [self pause];
        }
    }
}


- (void) setPlaying:(BOOL)playing
{
    if (_playing != playing) {
        _playing = playing;

        NSTimeInterval fadeDuration = playing ?
            [[Settings sharedInstance] playFadeDuration] :
            [[Settings sharedInstance] pauseFadeDuration];

        [self _startOrStopOutputWithFadeDuration:fadeDuration];
        
        [self _postNotificationName:AudioPlayerDidUpdateNotificationName];
        
        [[Settings sharedInstance] setPlaybackWasPlaying:playing];
    }
}


- (void) setMuted:(BOOL)muted
{
    if (_muted != muted) {
        _muted = muted;
        
        NSTimeInterval fadeDuration = [[Settings sharedInstance] muteFadeDuration];
        [self _startOrStopOutputWithFadeDuration:fadeDuration];

        [self _postNotificationName:AudioPlayerDidUpdateNotificationName];
    }
}


- (void) terminate
{
    _terminating = YES;
    [self _startOrStopOutputWithFadeDuration:sTerminateTime];
}


@end

