// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

@import Foundation;

@class Preset;

extern NSString * const AudioPlayerDidUpdateNotificationName;

@interface AudioPlayer : NSObject

+ (instancetype) sharedInstance;

// Either toggles playback or shows the current error.
- (void) performPlaybackAction;

- (void) play;
- (void) pause;

- (void) increaseVolume;
- (void) decreaseVolume;

- (void) checkPresetModificationDate;

- (void) terminate;

@property (nonatomic) Preset *preset;

@property (nonatomic) double volume;
@property (nonatomic) double stereoWidth;
@property (nonatomic) double stereoBalance;

@property (nonatomic, readonly, getter=isPlaying) BOOL playing;
@property (nonatomic, readonly) NSError *error;

@property (nonatomic, getter=isMuted) BOOL muted;

@end
