// (c) 2024-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "PresetManager.h"
#import "Utils.h"
#import "Preset.h"
#import "Settings.h"

@import AppKit;

static id sSharedInstance = nil;

NSString * const PresetsDidChangeNotificationName = @"PresetsDidChangeNotification";
NSString * const SelectedPresetDidChangeNotificationName = @"SelectedPresetDidChangeNotification";


@implementation PresetManager {
    FSEventStreamRef _eventStream;
    NSMutableDictionary *_identifierToPresetMap;

    NSInteger _updateCount;
    BOOL _needsPresetsDidChangeNotification;
    BOOL _needsSelectionDidChangeNotification;
}


+ (id) sharedInstance
{
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sSharedInstance = [[self alloc] init];
    });

    return sSharedInstance;
}


#pragma mark - Lifecycle

- (id) init
{
    if ((self = [super init])) {
        _identifierToPresetMap = [NSMutableDictionary dictionary];
        _allPresets = [NSArray array];
        _enabledPresets = [NSArray array];

        [self _setupPresetsFolder];
        [self _setupEventStream];
        [self _scanPresetsFolder];
    }

    return self;
}


- (void) dealloc
{
    if (_eventStream) {
        FSEventStreamInvalidate(_eventStream);
        CFRelease(_eventStream);
    }
}



#pragma mark - Private Methods

- (void) _beginUpdates
{
    _updateCount++;
}


- (void) _endUpdates
{
    __auto_type postNotification = ^(NSString *name) {
        [[NSNotificationCenter defaultCenter] postNotificationName:name object: self];
    };

    _updateCount--;
    
    if (_updateCount == 0) {
        if (_needsPresetsDidChangeNotification) {
            postNotification(PresetsDidChangeNotificationName);
            _needsPresetsDidChangeNotification = NO;
        }

        if (_needsSelectionDidChangeNotification) {
            postNotification(SelectedPresetDidChangeNotificationName);
            _needsSelectionDidChangeNotification = NO;
        }
    }
}


- (NSString *) _applicationSupportFolderPath
{
    NSString *name = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];

    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (![paths count]) return nil;

    NSString *resolvedPath = [paths firstObject];
    if (name) {
        resolvedPath = [resolvedPath stringByAppendingPathComponent:name];
    }

    return resolvedPath;
}


- (NSString *) _presetsFolderPath
{
    return [[self _applicationSupportFolderPath] stringByAppendingPathComponent:@"Presets"];
}


- (void) _setupPresetsFolder
{
    NSString *presetsFolderPath = [self _presetsFolderPath];

    if (![[NSFileManager defaultManager] fileExistsAtPath:presetsFolderPath]) {
        NSError *error;

        BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath: presetsFolderPath
                                                 withIntermediateDirectories: YES
                                                                  attributes: nil
                                                                       error: &error];

        if (!success) {
            NSLog(@"Could not create Presets folder at '%@' - %@", presetsFolderPath, error);
        }

        [self restoreDefaultPresets];
    }
}


static void sStreamCallback(
    ConstFSEventStreamRef streamRef,
    void *clientCallBackInfo,
    size_t numEvents,
    void *eventPaths,
    const FSEventStreamEventFlags *eventFlags,
    const FSEventStreamEventId *eventIds
) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [(__bridge PresetManager *)clientCallBackInfo _scanPresetsFolder];
    });
}


- (void) _setupEventStream
{
    FSEventStreamContext context = {
        0,
        (__bridge void *)self,
        NULL,
        NULL,
        NULL
    };

    _eventStream = FSEventStreamCreate(
        NULL,
        sStreamCallback,
        &context,
        (__bridge CFArrayRef) @[ [self _presetsFolderPath ] ],
        kFSEventStreamEventIdSinceNow,
        0,
        kFSEventStreamCreateFlagUseCFTypes
    );

    FSEventStreamSetDispatchQueue(_eventStream, dispatch_get_global_queue(0, 0));
        
    FSEventStreamStart(_eventStream);
}


- (void) _scanPresetsFolder
{
    NSString *folderPath = [self _presetsFolderPath];
    NSFileManager *manager = [NSFileManager defaultManager];

    if (![manager fileExistsAtPath:folderPath]) return;

    [self _beginUpdates];

    NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL: [NSURL fileURLWithPath:folderPath]
                                      includingPropertiesForKeys: @[ NSURLContentModificationDateKey ]
                                                         options: 0
                                                    errorHandler: nil];

    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSMutableArray *tmpPresets = [NSMutableArray array];

    for (NSURL *fileURL in enumerator) {
        NSString *identifier = [Preset identifierWithFileURL:fileURL];
        NSString *pathExtension = [fileURL pathExtension];

        if (![pathExtension isEqualToString:@"json"]) continue;

        NSDate *modificationDate = nil;
        [fileURL getResourceValue:&modificationDate forKey:NSURLContentModificationDateKey error:NULL];
        
        if (!modificationDate) continue;

        Preset *preset = [_identifierToPresetMap objectForKey:identifier];
        
        if (!preset) {
            BOOL enabled = [[[Settings sharedInstance] enabledPresetIdentifiers] containsObject:identifier];
            preset = [[Preset alloc] initWithFileURL:fileURL enabled:enabled];
        }

        if ([modificationDate isGreaterThan:[preset modificationDate]]) {
            [preset updateWithModificationDate:modificationDate];
            _needsPresetsDidChangeNotification = YES;
        }

        [tmpPresets addObject:preset];
        [map setObject:preset forKey:identifier];
    }

    // Create a new allPresets array
    {
        NSMutableArray *allPresets = [NSMutableArray array];

        for (Preset *preset in _allPresets) {
            if ([tmpPresets containsObject:preset]) {
                [allPresets addObject:preset];
                [tmpPresets removeObject:preset];
            }
        }

        [allPresets addObjectsFromArray:tmpPresets];
    }

    NSMutableArray *allPresets = [NSMutableArray array];

    // Make an ordered allPresets array based on existing orderedPresetIdentifiers
    for (NSString *identifier in [[Settings sharedInstance] orderedPresetIdentifiers]) {
        Preset *preset = [map objectForKey:identifier];
        
        if (preset) {
            [tmpPresets removeObject:preset];
            [allPresets addObject:preset];
        }
    }

    // Add remaining objects sorted by name
    [tmpPresets sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"identifier" ascending:YES] ]];
    [allPresets addObjectsFromArray:tmpPresets];

    NSString *selectedPresetIdentifier = [[Settings sharedInstance] selectedPresetIdentifier];

    [self setAllPresets:allPresets];

    _identifierToPresetMap = map;

    [self selectPresetWithIdentifier:selectedPresetIdentifier];

    [self _endUpdates];
}


- (NSArray<NSString *> *) _identifiersWithPresets:(NSArray<Preset *> *)presets
{
    NSMutableArray *identifiers = [NSMutableArray array];
    for (Preset *preset in presets) {
        [identifiers addObject:[preset identifier]];
    }

    return identifiers;
}


#pragma mark - Friend Methods

- (void) updateEnabledPresets
{
    NSMutableArray *enabledPresets = [NSMutableArray array];

    for (Preset *preset in [self allPresets]) {
        if ([preset isEnabled]) {
            [enabledPresets addObject:preset];
        }
    }

    [self _beginUpdates];

    [self setEnabledPresets:enabledPresets];

    if (![[self selectedPreset] isEnabled]) {
        [self selectPreset:nil];
    }

    [self _endUpdates];
}


#pragma mark - Public Methods

- (BOOL) isPresetSelected:(Preset *)preset
{
    if (preset && _selectedPreset) {
        return [_selectedPreset isEqual:preset];
    } else if (!preset && !_selectedPreset) {
        return YES;
    } else {
        return NO;
    }
}


- (BOOL) selectPreset:(Preset *)preset
{
    [self _beginUpdates];

    BOOL result = YES;

    if (!preset) {
        preset = [_enabledPresets firstObject];
        result = NO;
    }
    
    if (![_enabledPresets containsObject:preset]) {
        preset = [_enabledPresets firstObject];
        result = NO;
    }

    if (_selectedPreset != preset) {
        _selectedPreset = preset;
        _needsSelectionDidChangeNotification = YES;
    }
    
    [[Settings sharedInstance] setSelectedPresetIdentifier:[_selectedPreset identifier]];

    [self _endUpdates];

    return result;
}


- (BOOL) selectPresetAtIndex:(NSInteger)index
{
    if (index >= 0 && index < [_enabledPresets count]) {
        return [self selectPreset:[_enabledPresets objectAtIndex:index]];
    }
    
    return NO;
}


- (BOOL) selectPresetWithIdentifier:(NSString *)identifier
{
    Preset *presetToSelect = nil;
    BOOL foundPreset = NO;

    for (Preset *preset in _enabledPresets) {
        if ([[preset identifier] isEqualToString:identifier]) {
            presetToSelect = preset;
            foundPreset = YES;
            break;
        }
    }
    
    if (!presetToSelect) {
        presetToSelect = [_enabledPresets firstObject];
    }

    return [self selectPreset:presetToSelect] && foundPreset;
}


- (void) restoreDefaultPresets
{
    NSString *bundlePresetsFolder = [[NSBundle mainBundle] pathForResource:@"Presets" ofType:nil];
    NSString *userPresetsFolder   = [self _presetsFolderPath];

    for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundlePresetsFolder error:NULL]) {
        NSString *bundleFile = [bundlePresetsFolder stringByAppendingPathComponent:file];
        NSString *userFile   = [userPresetsFolder   stringByAppendingPathComponent:file];

        if (![[NSFileManager defaultManager] fileExistsAtPath:userFile]) {
            [[NSFileManager defaultManager] copyItemAtPath:bundleFile toPath:userFile error:NULL];
        }
    }
}


- (void) showPresetsFolder
{
    NSURL *URL = [NSURL fileURLWithPath:[self _presetsFolderPath]];
    [[NSWorkspace sharedWorkspace] openURL:URL];
}


#pragma mark - Accessors

- (void) setAllPresets:(NSArray<Preset *> *)allPresets
{
    [self _beginUpdates];

    if (![_allPresets isEqual:allPresets]) {
        _allPresets = [allPresets copy];
        _needsPresetsDidChangeNotification = YES;

        NSArray *identifiers = [self _identifiersWithPresets:allPresets];
        [[Settings sharedInstance] setOrderedPresetIdentifiers:identifiers];

        [self updateEnabledPresets];
    }

    [self _endUpdates];
}


- (void) setEnabledPresets:(NSArray<Preset *> *)enabledPresets
{
    [self _beginUpdates];

    if (![_enabledPresets isEqual:enabledPresets]) {
        _enabledPresets = [enabledPresets copy];
        _needsPresetsDidChangeNotification = YES;

        NSArray *identifiers = [self _identifiersWithPresets:enabledPresets];
        [[Settings sharedInstance] setEnabledPresetIdentifiers:identifiers];
    }

    [self _endUpdates];
}


@end
