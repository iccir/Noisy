// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "AppDelegate.h"
#import "MainWindowController.h"
#import "Settings.h"
#import "Shortcut.h"
#import "ShortcutManager.h"
#import "SettingsWindowController.h"
#import "ExportAudioController.h"
#import "PresetManager.h"
#import "AudioPlayer.h"
#import "Preset.h"
#import "AutoMuteManager.h"


@import AVFAudio;

@interface AppDelegate () <NSMenuDelegate, NSMenuItemValidation, ShortcutListener>

@property (nonatomic, strong) IBOutlet NSMenu *statusBarMenu;

@property (nonatomic, strong) IBOutlet NSMenuItem *mainMenuPresetsGroupStart;
@property (nonatomic, strong) IBOutlet NSMenuItem *statusItemMenuPresetGroupStart;
@property (nonatomic, strong) IBOutlet NSMenuItem *mainMenuAutoMuteStateMenuItem;

@property (nonatomic, strong) IBOutlet NSMenuItem *autoMuteStateMenuItem;
@property (nonatomic, strong) IBOutlet NSMenuItem *showControlsMenuItem;
@property (nonatomic, strong) IBOutlet NSMenuItem *quitSeparatorMenuItem;
@property (nonatomic, strong) IBOutlet NSMenuItem *quitMenuItem;

@end


@implementation AppDelegate {
    NSStatusItem *_statusItem;

    NSArray *_mainMenuPresetItems;
    NSArray *_statusBarPresetItems;
    
    MainWindowController *_mainWindowController;
    SettingsWindowController *_settingsWindowController;
    
    NSError *_modalError;
}


#pragma mark - NSApplication Delegate

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [Settings registerDefaults];
    [AutoMuteManager sharedInstance];

    Settings *settings = [Settings sharedInstance];
    BOOL shouldPlay = [settings rememberPlaybackState] && [settings playbackWasPlaying];

    [self setPresetManager:[PresetManager sharedInstance]];
    [self setSettings:[Settings sharedInstance]];
    [self setAudioPlayer:[AudioPlayer sharedInstance]];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_handleSettingsDidChange:)
                                                 name: SettingsDidChangeNotificationName
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_handlePresetsDidChange:)
                                                 name: PresetsDidChangeNotificationName
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_handleSelectedPresetDidChange:)
                                                 name: SelectedPresetDidChangeNotificationName
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_handleAutoMuteDidChange:)
                                                 name: AutoMuteDidChangeNotificationName
                                               object: nil];

    _mainWindowController = [[MainWindowController alloc] init];
    
    [self _handleSettingsDidChange:nil];
    [self _handlePresetsDidChange:nil];
    [self _handleSelectedPresetDidChange:nil];
    [self _handleAutoMuteDidChange:nil];

    if (shouldPlay) {
        [self togglePlayback:self];
    }

    if ([settings iconMode] != IconModeInMenuBar) {
        [_mainWindowController showWindow:self];
        [NSApp activateIgnoringOtherApps:YES];
    }
}


- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)sender
{
    AudioPlayer *player = [AudioPlayer sharedInstance];
    
    if ([player isPlaying]) {
        [[AudioPlayer sharedInstance] terminate];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSApp replyToApplicationShouldTerminate:YES];
        });
    
        return NSTerminateLater;

    } else {
        return NSTerminateNow;
    }
}


- (BOOL) applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)hasVisibleWindows
{
    if (!hasVisibleWindows) {
        [self showMainWindow:self];
    }

    return YES;
}


#pragma mark - Private Methods

- (void) _openURLString:(NSString *)urlString
{
    NSURL *URL = [NSURL URLWithString:urlString];
    [[NSWorkspace sharedWorkspace] openURL:URL];
}


- (void) _updateShortcuts
{
    Settings       *settings  = [Settings sharedInstance];
    NSMutableArray *shortcuts = [NSMutableArray array];

    if ([settings togglePlaybackShortcut]) {
        [shortcuts addObject:[settings togglePlaybackShortcut]];
    }

    if ([settings increaseVolumeShortcut]) {
        [shortcuts addObject:[settings increaseVolumeShortcut]];
    }

    if ([settings decreaseVolumeShortcut]) {
        [shortcuts addObject:[settings decreaseVolumeShortcut]];
    }

    if ([shortcuts count] || [ShortcutManager hasSharedInstance]) {
        [[ShortcutManager sharedInstance] addListener:self];
        [[ShortcutManager sharedInstance] setShortcuts:shortcuts];
    }
}


- (void) _updateDockAndMenuBar
{
    IconMode iconMode = [[Settings sharedInstance] iconMode];

    if (iconMode == IconModeInMenuBar || iconMode == IconModeInBoth) {
        if (!_statusItem) {
            _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];


            [_statusItem setMenu:_statusBarMenu];
            [_statusBarMenu setDelegate:self];

            [_statusItem setMenu:[self statusBarMenu]];
        }
        
        [self _updateStatusBarIcon];

    } else {
        if (_statusItem) {
            [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
            _statusItem = nil;
        }
    }
    
    if (iconMode == IconModeInMenuBar) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    } else {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    }
}


- (void) _updateStatusBarIcon
{
    NSImage *image = [[AutoMuteManager sharedInstance] shouldMute] ?
        [NSImage imageNamed:@"StatusBarIconAutoMute"] :
        [NSImage imageNamed:@"StatusBarIcon"];
        
    [[_statusItem button] setImage:image];
}


#pragma mark - Notifications

- (void) _handleSettingsDidChange:(NSNotification *)note
{
    [self _updateShortcuts];
    [self _updateDockAndMenuBar];
}


- (void) _handlePresetsDidChange:(NSNotification *)note
{
    AudioPlayer *audioPlayer = [AudioPlayer sharedInstance];

    Preset  *activePreset    = [audioPlayer preset];

    NSArray *enabledPresets = [[PresetManager sharedInstance] enabledPresets];

    __auto_type makeMenuItem = ^(Preset *preset, NSString *title, NSString *keyEquivalent) {
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle: title
                                                          action: @selector(changeSelectedPreset:)
                                                   keyEquivalent: keyEquivalent];
                                                   
        [menuItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
        [menuItem setRepresentedObject:preset];
        [menuItem setTarget:self];

        return menuItem;
    };

    __auto_type removeMenuItems = ^(NSArray *menuItems) {
        for (NSMenuItem *menuItem in menuItems) {
            [[menuItem menu] removeItem:menuItem];
        }
    };

    __auto_type addMenuItems = ^(NSArray *menuItems, NSMenuItem *after) {
        NSMenu *menu = [after menu];
        NSInteger index = [menu indexOfItem:after];
        
        for (NSMenuItem *menuItem in [menuItems reverseObjectEnumerator]) {
            [menu insertItem:menuItem atIndex:index + 1];
        }
    };
    
    if (![enabledPresets containsObject:activePreset]) {
        [audioPlayer setPreset:nil];
        [audioPlayer pause];
    }
    
    [audioPlayer checkPresetModificationDate];
    
    BOOL makeMainMenuPresetItems = [enabledPresets count] <= 5;

    NSMutableArray *mainMenuPresetItems  = [NSMutableArray array];
    NSMutableArray *statusBarPresetItems = [NSMutableArray array];
    
    removeMenuItems(_mainMenuPresetItems);
    removeMenuItems(_statusBarPresetItems);

    NSInteger keyEquivalentNumber = 1;

    for (Preset *preset in enabledPresets) {
        NSString *name = [preset name];

        if (makeMainMenuPresetItems) {
            NSString *title = [NSString stringWithFormat:@"Select %@", name];
            NSString *keyEquivalent = [NSString stringWithFormat:@"%ld", (long)keyEquivalentNumber];

            [mainMenuPresetItems addObject:makeMenuItem(preset, title, keyEquivalent)];
            
            keyEquivalentNumber++;
        }
        
        [statusBarPresetItems addObject:makeMenuItem(preset, name, @"")];
    }
    
    if (makeMainMenuPresetItems) {
        addMenuItems(mainMenuPresetItems, _mainMenuPresetsGroupStart);
        [_mainMenuPresetsGroupStart setHidden:NO];
    } else {
        [_mainMenuPresetsGroupStart setHidden:YES];
    }

    addMenuItems(statusBarPresetItems, _statusItemMenuPresetGroupStart);

    _mainMenuPresetItems  = mainMenuPresetItems;
    _statusBarPresetItems = statusBarPresetItems;
}


- (void) _handleSelectedPresetDidChange:(NSNotification *)note
{
    Preset *selectedPreset = [[PresetManager sharedInstance] selectedPreset];

    [[AudioPlayer sharedInstance] setPreset:selectedPreset];
}


- (void) _handleAutoMuteDidChange:(NSNotification *)note
{
    BOOL shouldMute = [[AutoMuteManager sharedInstance] shouldMute];

    [_mainMenuAutoMuteStateMenuItem setHidden:!shouldMute];
    [_autoMuteStateMenuItem         setHidden:!shouldMute];

    [self _updateStatusBarIcon];

    [[AudioPlayer sharedInstance] setMuted:shouldMute];
}


- (void) menuNeedsUpdate:(NSMenu *)menu
{
    IconMode iconMode = [[Settings sharedInstance] iconMode];
    
    BOOL iconModeInMenuBar = (iconMode == IconModeInMenuBar);
    
    [_showControlsMenuItem  setHidden:!iconModeInMenuBar];
    [_quitSeparatorMenuItem setHidden:!iconModeInMenuBar];
    [_quitMenuItem          setHidden:!iconModeInMenuBar];
}


- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
    BOOL isStatusBarMenu = [[menuItem menu] isEqual:_statusBarMenu];

    if ([menuItem action] == @selector(togglePlayback:)) {
        AudioPlayer *player = [AudioPlayer sharedInstance];
        
        if ([player error]) {
            [menuItem setTitle:NSLocalizedString(@"SHOW_ERROR", @"Menu title: 'Show error'")];
        } else if ([player isPlaying]) {
            [menuItem setTitle:NSLocalizedString(@"PAUSE", @"Menu title: 'Pause'")];
        } else {
            [menuItem setTitle:NSLocalizedString(@"PLAY", @"Menu title: 'Play'")];
        }
    
    } else if ([menuItem action] == @selector(changeSelectedPreset:) && isStatusBarMenu) {
        Preset *preset = [menuItem representedObject];
        
        BOOL isSelected = [[PresetManager sharedInstance] isPresetSelected:preset];
        [menuItem setState:(isSelected ? NSControlStateValueOn : NSControlStateValueOff)];

    } else if ([menuItem action] == @selector(showMainWindow:) && !isStatusBarMenu) {
        BOOL yn = [_mainWindowController isWindowLoaded] && [[_mainWindowController window] isMainWindow];
        [menuItem setState:(yn ? NSControlStateValueOn : NSControlStateValueOff)];
    }

    return YES;
}


#pragma mark - ShortcutListener

- (BOOL) performShortcut:(Shortcut *)shortcut
{
    Settings *settings = [Settings sharedInstance];
    BOOL yn = NO;
    
    if ([[settings togglePlaybackShortcut] isEqual:shortcut]) {
        [self togglePlayback:self];
        yn = YES;

    } else if ([[settings decreaseVolumeShortcut] isEqual:shortcut]) {
        [self decreaseVolume:self];
        yn = YES;

    } else if ([[settings decreaseVolumeShortcut] isEqual:shortcut]) {
        [self increaseVolume:self];
        yn = YES;
    }

    return yn;
}


#pragma mark - Public Methods

- (void) showProgramError:(NSError *)error
{
    if (_modalError) {
        [NSApp abortModal];
    
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showProgramError:error];
        });
    
        return;

    } else {
        _modalError = error;

        NSAlert *alert = [[NSAlert alloc] init];
        
        NSString *informativeText = [[error userInfo] objectForKey:NSDebugDescriptionErrorKey];
        
        [alert setMessageText:[error localizedDescription]];
        [alert setInformativeText:informativeText];

        [alert runModal];

        _modalError = nil;
    }
}


#pragma mark - IBActions

- (IBAction) exportAudio:(id)sender
{
    ExportAudioController *exportAudioController = [[ExportAudioController alloc] init];
    
    Preset *preset = [[PresetManager sharedInstance] selectedPreset];
    
    if (preset) {
        [exportAudioController presentSavePanelForPreset:preset];
    }
}


- (IBAction) showMainWindow:(id)sender
{
    [[self mainWindowController] showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}


- (IBAction) showSettings:(id)sender
{
    [[self settingsWindowController] showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}


- (IBAction) togglePlayback:(id)sender
{
    [[AudioPlayer sharedInstance] performPlaybackAction];
}


- (IBAction) changeSelectedPreset:(id)sender
{
    [[PresetManager sharedInstance] selectPreset:[sender representedObject]];
}


- (IBAction) increaseVolume:(id)sender
{
    [[AudioPlayer sharedInstance] increaseVolume];
}


- (IBAction) decreaseVolume:(id)sender
{
    [[AudioPlayer sharedInstance] decreaseVolume];
}


- (IBAction) openWhiteNoisePage:(id)sender
{
    [self _openURLString:@"https://en.wikipedia.org/wiki/White_noise"];
}


- (IBAction) openPinkNoisePage:(id)sender
{
    [self _openURLString:@"https://en.wikipedia.org/wiki/Pink_noise"];
}


- (IBAction) openBrownNoisePage:(id)sender
{
    [self _openURLString:@"https://en.wikipedia.org/wiki/Brownian_noise"];
}


#pragma mark - Accessors

- (SettingsWindowController *) settingsWindowController
{
    if (!_settingsWindowController) {
        _settingsWindowController = [[SettingsWindowController alloc] init];
    }
    
    return _settingsWindowController;
}


@end
