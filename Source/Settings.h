// (c) 2011-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

extern NSString * const SettingsDidChangeNotificationName;

@class Shortcut;


typedef NS_ENUM(NSInteger, IconMode) {
    IconModeInMenuBar = 0,
    IconModeInDock    = 1,
    IconModeInBoth    = 2
};


@interface Settings : NSObject

+ (void) registerDefaults;

+ (instancetype) sharedInstance;

@property (nonatomic) BOOL rememberPlaybackState;
@property (nonatomic) BOOL playbackWasPlaying;
@property (nonatomic) double volume;
@property (nonatomic) double stereoWidth;
@property (nonatomic) double stereoBalance;

@property (nonatomic) IconMode iconMode;

@property (nonatomic) Shortcut *togglePlaybackShortcut;
@property (nonatomic) Shortcut *increaseVolumeShortcut;
@property (nonatomic) Shortcut *decreaseVolumeShortcut;

@property (nonatomic) NSArray<NSString *> *enabledPresetIdentifiers;
@property (nonatomic) NSArray<NSString *> *orderedPresetIdentifiers;

@property (nonatomic) NSString *selectedPresetIdentifier;

@property (nonatomic) NSArray<NSString *> *autoMuteBundleIdentifiers;

@property (nonatomic) BOOL muteForMusicApps;
@property (nonatomic) BOOL muteForNowPlaying;

// Advanced/Hidden settings
@property (nonatomic) BOOL useNowPlayingSPI;
@property (nonatomic) NSTimeInterval playFadeDuration;
@property (nonatomic) NSTimeInterval pauseFadeDuration;
@property (nonatomic) NSTimeInterval muteFadeDuration;

@end
