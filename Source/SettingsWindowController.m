// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "SettingsWindowController.h"

#import "Settings.h"
#import "ShortcutView.h"
#import "AutoMuteManager.h"
#import "PresetManager.h"
#import "AudioPlayer.h"
#import "Preset.h"

@import UniformTypeIdentifiers;

static NSString *sPresetTableRowType = @"com.iccir.Noisy.PresetTableRow";


@implementation SettingsWindowController {
    NSInteger _draggedPresetRow;
}


+ (NSString *) presetTableRowDragType
{
    NSString *mainBundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    return [NSString stringWithFormat:@"%@.PresetDragType", mainBundleIdentifier];
}


- (id) initWithWindow:(NSWindow *)window
{
    if ((self = [super initWithWindow:window])) {
        [self setSettings:[Settings sharedInstance]];
        [self setPresetsManager:[PresetManager sharedInstance]];
        [self setAutoMuteManager:[AutoMuteManager sharedInstance]];
        [self setAudioPlayer:[AudioPlayer sharedInstance]];
        
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(_handleSettingsDidChange:)
                                                     name: SettingsDidChangeNotificationName
                                                   object: nil];
    }

    return self;
}


- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (NSString *) windowNibName
{
    return @"Settings";
}


- (void ) windowDidLoad
{
    [_presetsTableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
	[_presetsTableView registerForDraggedTypes:@[ [SettingsWindowController presetTableRowDragType] ]];
    [_presetsTableView setVerticalMotionCanBeginDrag:YES];

    [self _handleSettingsDidChange:nil];
    [self selectPane:0 animated:NO];

    if (![AutoMuteManager isNowPlayingSPIEnabled]) {
        [_muteAppsBottomConstraint setConstant:20];
        [_muteNowPlayingCheckbox setHidden:YES];
    }
}


#pragma mark - Private Methods

- (void) _handleSettingsDidChange:(NSNotification *)note
{
    Settings *settings = [Settings sharedInstance];

    [_togglePlaybackShortcutView  setShortcut:[settings togglePlaybackShortcut]];
    [_decreaseVolumeShortcutView  setShortcut:[settings decreaseVolumeShortcut]];
    [_increaseVolumeShortcutView  setShortcut:[settings increaseVolumeShortcut]];
}


#pragma mark - Table View Delegate / Data Source

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

- (BOOL) tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
    if (tableView == _presetsTableView) {
        if ([rowIndexes count] != 1) return NO;
        
        NSInteger row = [rowIndexes firstIndex];
        
        NSArray *array = [[self presetsArrayController] arrangedObjects];
        Preset *preset = (row < [array count]) ? [array objectAtIndex:row] : nil;

        if (!preset) return NO;

        _draggedPresetRow = row;
        [pboard setData:[NSData data] forType:[SettingsWindowController presetTableRowDragType]];
        
        return YES;

    } else {
        return NO;
    }
}


#pragma clang diagnostic pop


- (NSDragOperation) tableView: (NSTableView *) tableView
                 validateDrop: (id <NSDraggingInfo>) info
                  proposedRow: (NSInteger) row
        proposedDropOperation: (NSTableViewDropOperation) dropOperation

{
    if (tableView == _presetsTableView) {
        return dropOperation == NSTableViewDropOn ? NSDragOperationNone : NSDragOperationMove;
    } else {
        return NSDragOperationNone;
    }
}


- (BOOL) tableView: (NSTableView *) tableView
        acceptDrop: (id <NSDraggingInfo>)info
               row: (NSInteger) row
     dropOperation: (NSTableViewDropOperation) dropOperation
{
    if (tableView == _presetsTableView) {
        
        NSArrayController *arrayController = [self presetsArrayController];
        NSArray *array = [arrayController arrangedObjects];
        
        Preset *draggedPreset = nil;
        if (_draggedPresetRow >= 0 && _draggedPresetRow < [array count]) {
            draggedPreset = [array objectAtIndex:_draggedPresetRow];
        }
        
        if (draggedPreset) {
            if (row >= _draggedPresetRow) {
                row--;
            }

            [arrayController removeObject:draggedPreset];
            [arrayController insertObject:draggedPreset atArrangedObjectIndex:row];
            
            return YES;
        }
    }

    return NO;
}


#pragma mark - Public Methods

- (void) selectPane:(NSInteger)tag animated:(BOOL)animated
{
    NSToolbarItem *item;
    NSView *pane;
    NSString *title;

    if (tag == 0) {
        item = _generalItem;
        pane = _generalPane;
        title = NSLocalizedString(@"GENERAL_TITLE", @"Settings title: 'General'");

    } else if (tag == 1) {
        item = _keyboardItem;
        pane = _keyboardPane;
        title = NSLocalizedString(@"KEYBOARD_TITLE", @"Settings title: 'Keyboard'");

    } else if (tag == 2) {
        item = _autoMuteItem;
        pane = _autoMutePane;
        title = NSLocalizedString(@"AUTO_MUTE_TITLE", @"Settings title: 'Auto Mute'");

    } else if (tag == 3) {
        item = _presetsItem;
        pane = _presetsPane;
        title = NSLocalizedString(@"PRESETS_TITLE", @"Settings title: 'Presets'");

    } else {
        return;
    }
    
    [_toolbar setSelectedItemIdentifier:[item itemIdentifier]];
    
    NSWindow *window = [self window];
    NSView *contentView = [window contentView];
    for (NSView *view in [contentView subviews]) {
        [view removeFromSuperview];
    }

    NSRect paneFrame = [pane frame];
    NSRect windowFrame = [window frame];
    NSRect newFrame = [window frameRectForContentRect:paneFrame];
    
    newFrame.origin    = windowFrame.origin;
    newFrame.origin.y += (windowFrame.size.height - newFrame.size.height);

    [pane setFrameOrigin:NSZeroPoint];

    [window setFrame:newFrame display:YES animate:animated];
    [window setTitle:title];

    [contentView addSubview:pane];
}


- (IBAction) selectPane:(id)sender
{
    [self selectPane:[sender tag] animated:YES];
}


- (IBAction) updatePreferences:(id)sender
{
    Settings *settings = [Settings sharedInstance];

    if (sender == _togglePlaybackShortcutView) {
        [settings setTogglePlaybackShortcut:[sender shortcut]];

    } else if (sender == _decreaseVolumeShortcutView) {
        [settings setDecreaseVolumeShortcut:[sender shortcut]];

    } else if (sender == _increaseVolumeShortcutView) {
        [settings setIncreaseVolumeShortcut:[sender shortcut]];
    }
}


- (IBAction) updateStereoBalance:(id)sender
{
    double value = [sender doubleValue];
    double snapThreshold = 0.03;
    
    if (value < snapThreshold && value > -snapThreshold) {
        value = 0;
        [sender setDoubleValue:value];
    }
    
    [[self audioPlayer] setStereoBalance:value];
}


#pragma mark - IBActions

- (IBAction) restoreDefaultPresets:(id)sender
{
    [[PresetManager sharedInstance] restoreDefaultPresets];
}


- (IBAction) showPresetsFolder:(id)sender
{
    [[PresetManager sharedInstance] showPresetsFolder];
}


- (IBAction) addAutoMuteApplication:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    
    [openPanel setAllowedContentTypes:@[ UTTypeApplicationBundle ]];
    
    [openPanel beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;

        NSBundle *bundle = [NSBundle bundleWithURL:[openPanel URL]];

        if (bundle) {
            [[AutoMuteManager sharedInstance] addEntryWithBundleIdentifier:[bundle bundleIdentifier]];
        }
    }];
}


@end
