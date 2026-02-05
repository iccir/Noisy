// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "MainWindowController.h"

#import "BackgroundView.h"
#import "PresetManager.h"
#import "Preset.h"
#import "AudioPlayer.h"
#import "Settings.h"
#import "VolumeSlider.h"
#import "PlayButton.h"


@interface MainWindowController ()

@property (nonatomic, strong) IBOutlet NSTextField *noEnabledPresetsLabel;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *segmentedControl;
@property (nonatomic, strong) IBOutlet NSPopUpButton *popUpButton;

@property (nonatomic, weak) IBOutlet PlayButton *playButton;
@property (nonatomic, weak) IBOutlet NSView *containerView;
@property (nonatomic, weak) IBOutlet NSImageView *autoMuteIconView;
@property (nonatomic, weak) IBOutlet VolumeSlider *volumeSlider;

@end


@implementation MainWindowController {
    BackgroundView *_backgroundView;
    CGFloat _segmentedControlDesiredWidth;
}


- (NSNibName) windowNibName
{
    return @"MainWindow";
}


- (void) awakeFromNib
{
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
                                             selector: @selector(_handleAudioPlayerDidUpdate:)
                                                 name: AudioPlayerDidUpdateNotificationName
                                               object: nil];

    [[self segmentedControl] setAutoresizingMask:NSViewWidthSizable];

    [_containerView addSubview:_popUpButton];
    [_containerView addSubview:_segmentedControl];
    
    CGRect containerFrame = [_containerView frame];
    containerFrame = CGRectInset(containerFrame, -5, 0);
    [_containerView setFrame:containerFrame];

    CGRect containerBounds = [_containerView bounds];

    [_popUpButton setFrame:CGRectInset(containerBounds, 1, 0)];
    [_popUpButton setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];

    [_segmentedControl setFrame:containerBounds];
    [_segmentedControl setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];

    NSView *contentView = [[self window] contentView];

    [_autoMuteIconView setHidden:NO];
    [_autoMuteIconView setAlphaValue:0];
    [_autoMuteIconView setContentTintColor:[NSColor colorNamed:@"ButtonTintColor"]];

    _backgroundView = [[BackgroundView alloc] init];
    [_backgroundView setFrame:[contentView bounds]];
    [_backgroundView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];

    [contentView addSubview:_backgroundView positioned:NSWindowBelow relativeTo:nil];

    [self _handlePresetsDidChange:nil];
    [self _handleSelectedPresetDidChange:nil];
    [self _handleAudioPlayerDidUpdate:nil];
    [self _handleSettingsDidChange:nil];
    
    [[self window] setExcludedFromWindowsMenu:YES];
}


- (void) windowDidBecomeMain:(NSNotification *)notification
{
    [_backgroundView setNeedsDisplay:YES];
}


- (void) windowDidResignMain:(NSNotification *)notification
{
    [_backgroundView setNeedsDisplay:YES];
}


- (void) windowDidResize:(NSNotification *)notification
{
    [self _updateSelectionControl];
}


#pragma mark - Private Methods

- (void) _updateSelectionControl
{
    NSArray *enabledPresets  = [[PresetManager sharedInstance] enabledPresets];
    NSView *viewToShow = nil;

    if ([enabledPresets count] == 0) {
        viewToShow = _noEnabledPresetsLabel;
    } else if ([_containerView frame].size.width >= _segmentedControlDesiredWidth) {
        viewToShow = _segmentedControl;
    } else {
        viewToShow = _popUpButton;
    }

    [_noEnabledPresetsLabel setHidden:(viewToShow != _noEnabledPresetsLabel)];
    [_segmentedControl      setHidden:(viewToShow != _segmentedControl)];
    [_popUpButton           setHidden:(viewToShow != _popUpButton)];
}


- (void) _updatePlaybackEnabled
{
    BOOL hasSelectedPreset = [[PresetManager sharedInstance] selectedPreset] != nil;
    [_playButton setEnabled:hasSelectedPreset];
}


#pragma mark - Notification Handlers

- (void) _handleSettingsDidChange:(NSNotification *)note
{
    [self _updateSelectionControl];
}


- (void) _handlePresetsDidChange:(NSNotification *)note
{
    NSArray *enabledPresets = [[PresetManager sharedInstance] enabledPresets];

    [_popUpButton removeAllItems];

    [_segmentedControl setSegmentCount:[enabledPresets count]];
    NSInteger segmentIndex = 0;

    for (Preset *preset in enabledPresets) {
        [_popUpButton addItemWithTitle:[preset name]];

        [_segmentedControl setLabel:[preset name] forSegment:segmentIndex];
        segmentIndex++;
    }
    
    [_segmentedControl setSegmentDistribution:NSSegmentDistributionFill];
    [_segmentedControl sizeToFit];
    _segmentedControlDesiredWidth = [_segmentedControl frame].size.width;
    [_segmentedControl setFrame:[_containerView bounds]];

    [self _handleSelectedPresetDidChange:nil];

    [self _updateSelectionControl];
}


- (void) _handleSelectedPresetDidChange:(NSNotification *)note
{
    NSArray *enabledPresets = [[PresetManager sharedInstance] enabledPresets];
    Preset  *selectedPreset = [[PresetManager sharedInstance] selectedPreset];

    NSUInteger index = [enabledPresets indexOfObject:selectedPreset];

    if (index != NSNotFound) {
        [_segmentedControl setSelectedSegment:index];
        [_popUpButton selectItemAtIndex:index];
    }
    
    [self _updatePlaybackEnabled];
}


- (void) _handleAudioPlayerDidUpdate:(NSNotification *)note
{
    AudioPlayer *player = [AudioPlayer sharedInstance];

    BOOL isPlaying = [player isPlaying];
    BOOL isMuted   = [player isMuted];

    NSImage *iconImage;
    NSColor *iconColor;

    if ([player error]) {
        iconImage = [NSImage imageNamed:@"ErrorIcon"];
        iconColor = [NSColor colorNamed:@"ButtonIconErrorColor"];

    } else if (isPlaying) {
        iconImage = [NSImage imageNamed:@"PauseIcon"];
        iconColor = [NSColor colorNamed:@"ButtonIconColor"];

    } else {
        iconImage = [NSImage imageNamed:@"PlayIcon"];
        iconColor = [NSColor colorNamed:@"ButtonIconColor"];
    }
    
    [_playButton setImage:iconImage];
    [_playButton setIconColor:iconColor];
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:0.5];
        [[_autoMuteIconView animator] setAlphaValue:(isPlaying && isMuted) ? 1.0 : 0.0];
    }];
}


#pragma mark - IBActions

- (IBAction) togglePlayback:(id)sender
{
    [[AudioPlayer sharedInstance] performPlaybackAction];
}


- (IBAction) handleSegmentSelected:(id)sender
{
    NSInteger index = [_segmentedControl selectedSegment];
    [[PresetManager sharedInstance] selectPresetAtIndex:index];
}


- (IBAction) handlePopUpButtonSelected:(id)sender
{
    NSMenuItem *selectedItem = [_popUpButton selectedItem];

    if (selectedItem) {
        NSInteger index = [_popUpButton indexOfItem:selectedItem];
        [[PresetManager sharedInstance] selectPresetAtIndex:index];
    }
}


@end
