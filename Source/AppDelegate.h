// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

@import AppKit;

@class MainWindowController;
@class SettingsWindowController;
@class Settings, PresetManager, AudioPlayer;

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (void) showProgramError:(NSError *)error;

@property (nonatomic, readonly) MainWindowController *mainWindowController;
@property (nonatomic, readonly) SettingsWindowController *settingsWindowController;

// For bindings
@property (nonatomic, weak) Settings *settings;
@property (nonatomic, weak) PresetManager *presetManager;
@property (nonatomic, weak) AudioPlayer *audioPlayer;

@end

