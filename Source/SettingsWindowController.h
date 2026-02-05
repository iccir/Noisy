// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

@import AppKit;

@class AutoMuteManager;
@class PresetsManager;
@class Settings;
@class ShortcutView;
@class AudioPlayer;

@interface SettingsWindowController : NSWindowController

- (void) selectPane:(NSInteger)tag animated:(BOOL)animated;

- (IBAction) selectPane:(id)sender;
- (IBAction) updatePreferences:(id)sender;

- (IBAction) updateStereoBalance:(id)sender;

- (IBAction) restoreDefaultPresets:(id)sender;
- (IBAction) showPresetsFolder:(id)sender;

// For bindings
@property (nonatomic, weak) Settings *settings;
@property (nonatomic, weak) PresetsManager *presetsManager;
@property (nonatomic, weak) AutoMuteManager *autoMuteManager;
@property (nonatomic, weak) AudioPlayer *audioPlayer;

// Outlets
@property (nonatomic, weak) IBOutlet NSToolbar *toolbar;
@property (nonatomic, weak) IBOutlet NSToolbarItem *generalItem;
@property (nonatomic, weak) IBOutlet NSToolbarItem *keyboardItem;
@property (nonatomic, weak) IBOutlet NSToolbarItem *autoMuteItem;
@property (nonatomic, weak) IBOutlet NSToolbarItem *presetsItem;

@property (nonatomic, strong) IBOutlet NSView *generalPane;
@property (nonatomic, strong) IBOutlet NSView *keyboardPane;
@property (nonatomic, strong) IBOutlet NSView *autoMutePane;
@property (nonatomic, strong) IBOutlet NSView *presetsPane;

@property (nonatomic, weak) IBOutlet NSArrayController *presetsArrayController;
@property (nonatomic, weak) IBOutlet NSTableView *presetsTableView;

@property (nonatomic, weak) IBOutlet NSLayoutConstraint *muteAppsBottomConstraint;
@property (nonatomic, weak) IBOutlet NSButton *muteNowPlayingCheckbox;

@property (nonatomic, weak) IBOutlet ShortcutView *togglePlaybackShortcutView;
@property (nonatomic, weak) IBOutlet ShortcutView *toggleAutoLevelShortcutView;
@property (nonatomic, weak) IBOutlet ShortcutView *decreaseVolumeShortcutView;
@property (nonatomic, weak) IBOutlet ShortcutView *increaseVolumeShortcutView;

@end
