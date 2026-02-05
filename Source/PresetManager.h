// (c) 2024-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

@import Foundation;

@class Preset;

extern NSString * const PresetsDidChangeNotificationName;
extern NSString * const SelectedPresetDidChangeNotificationName;


@interface PresetManager : NSObject

+ (id) sharedInstance;

- (void) restoreDefaultPresets;
- (void) showPresetsFolder;

@property (nonatomic, copy) NSArray<Preset *> *allPresets;
@property (nonatomic, copy) NSArray<Preset *> *enabledPresets;

// These return NO if the requested preset was not selected
- (BOOL) selectPreset:(Preset *)preset;
- (BOOL) selectPresetAtIndex:(NSInteger)index;
- (BOOL) selectPresetWithIdentifier:(NSString *)identifier;

// Handled nil preset
- (BOOL) isPresetSelected:(Preset *)preset;

@property (nonatomic, readonly) Preset *selectedPreset;

@end

