// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

@import AppKit;

@class Preset;

@interface ExportAudioController : NSViewController

- (void) presentSavePanelForPreset:(Preset *)preset;

@end
