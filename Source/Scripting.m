// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "Scripting.h"

#import "PresetManager.h"
#import "AudioPlayer.h"
#import "Preset.h"

@import AppKit;


@interface NSApplication (Scripting)
@end


@implementation NSApplication (Scripting)


- (void) handlePlayScriptCommand:(NSScriptCommand *)command
{
    [[AudioPlayer sharedInstance] play];
}


- (void) handlePauseScriptCommand:(NSScriptCommand *)command
{
    [[AudioPlayer sharedInstance] pause];
}


- (NSArray *) scriptingAvailablePresetNames
{
    NSMutableArray *results = [NSMutableArray array];

    for (Preset *preset in [[PresetManager sharedInstance] enabledPresets]) {
        NSString *name = [preset name];

        if (![results containsObject:name]) {
            [results addObject:name];
        }
    }
    
    return results;
}


- (void) setScriptingPlaying:(NSNumber *)number
{
    if ([number boolValue]) {
        [[AudioPlayer sharedInstance] play];
    } else {
        [[AudioPlayer sharedInstance] pause];
    }
}


- (NSNumber *) scriptingPlaying
{
    return [[AudioPlayer sharedInstance] isPlaying] ? @1 : @0;
}


- (void) setScriptingSelectedPresetName:(NSString *)presetName
{
    BOOL foundPreset = NO;
    
    for (Preset *preset in [[PresetManager sharedInstance] enabledPresets]) {
        if ([[preset name] isEqualToString:presetName]) {
            if ([[PresetManager sharedInstance] selectPreset:preset]) {
                foundPreset = YES;
                break;
            }
        }
    }
    
    if (!foundPreset) {
        NSScriptCommand* c = [NSScriptCommand currentCommand];
        [c setScriptErrorNumber:errAECoercionFail];
        [c setScriptErrorString:[NSString stringWithFormat:@"No preset named '%@'", presetName]];
    }
}


- (NSString *) scriptingSelectedPresetName
{
    return [[[PresetManager sharedInstance] selectedPreset] name];
}


- (void) setScriptingVolume:(NSNumber *)number
{
    [[AudioPlayer sharedInstance] setVolume:[number doubleValue]];
}


- (NSNumber *) scriptingVolume
{
    return @([[AudioPlayer sharedInstance] volume]);
}


@end



