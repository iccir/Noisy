// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "ExportAudioController.h"
#import "NoisyProgram.h"

#import "Preset.h"
#import "StereoField.h"

@import UniformTypeIdentifiers;
@import AVFAudio;
@import AudioToolbox.AudioFile;

@interface ExportAudioController ()
@property (nonatomic) NSString *duration;
@property (nonatomic) NSInteger sampleRate;
@property (nonatomic) NSInteger channelCount;
@end

@implementation ExportAudioController

- (NSNibName) nibName
{
    return @"ExportAudio";
}


- (void) _exportAudioWithPreset:(Preset *)preset toFileURL:(NSURL *)fileURL
{
    NSLog(@"Export %@ %ld %ld, fileURL: %@", _duration, _sampleRate, _channelCount, fileURL);
    
    NSError *error = nil;
    
    double sampleRate = _sampleRate;
    NSInteger framesRemaining = [_duration doubleValue] * sampleRate;
    AVAudioFrameCount frameCapacity = (AVAudioFrameCount)(sampleRate * 10);
    AVAudioChannelCount channelCount = (AVAudioChannelCount)_channelCount;

    NSDictionary *settings = @{
        AVAudioFileTypeKey: @(kAudioFileWAVEType),
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @(_sampleRate),
        AVNumberOfChannelsKey: @(_channelCount),
        AVEncoderBitDepthHintKey: @(16)
    };
    
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForWriting:fileURL settings:settings error:&error];

    AVAudioFormat *bufferFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:_sampleRate channels:channelCount];
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:bufferFormat frameCapacity:frameCapacity];

    if (!error) {
        NoisyProgram *program = NoisyProgramCreate(preset, channelCount, sampleRate, &error);

        float *left  = channelCount > 0 ? [buffer floatChannelData][0] : NULL;
        float *right = channelCount > 1 ? [buffer floatChannelData][1] : NULL;

        while (!error && framesRemaining > 0) {
            AVAudioFrameCount frameLength = (AVAudioFrameCount)MIN(framesRemaining, frameCapacity);
            
            NoisyProgramProcess(program, left, right, frameLength);
            
            float leftAutoGain, rightAutoGain;
            NoisyProgramGetAutoGain(program, &leftAutoGain, &rightAutoGain);
            ApplyStereoFieldVolumeAndBalance(leftAutoGain, rightAutoGain, 0.0, left, right, frameLength);

            [buffer setFrameLength:frameLength];
            [audioFile writeFromBuffer:buffer error:&error];
            
            framesRemaining -= frameLength;
        }

        NoisyProgramFree(program);
    }

    if (error) {
        [[NSAlert alertWithError:error] runModal];
    }
}


- (void) presentSavePanelForPreset:(Preset *)preset
{
    [self setDuration:@"300"];
    [self setSampleRate:44100];
    [self setChannelCount:2];
    
    NSSavePanel *savePanel = [NSSavePanel savePanel];

    [savePanel setTitle:NSLocalizedString(@"EXPORT_AUDIO_TITLE", @"Save panel title: 'Export Audio'")];

    UTType *wavType = [UTType typeWithFilenameExtension:@"wav"];

    [savePanel setAllowedContentTypes:@[ wavType ]];
    [savePanel setNameFieldStringValue:[preset name]];
    [savePanel setAccessoryView:[self view]];

    [savePanel beginWithCompletionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK) {
            [self _exportAudioWithPreset:preset toFileURL:[savePanel URL]];
            [savePanel setAccessoryView:nil];
        }
    }];

}

@end
