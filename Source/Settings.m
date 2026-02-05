// (c) 2011-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "Settings.h"
#import "Shortcut.h"


NSString * const SettingsDidChangeNotificationName = @"SettingsDidChange";


static NSDictionary *sGetDefaultValues(void)
{
    static NSDictionary *sDefaultValues = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sDefaultValues = @{
            @"iconMode": @(IconModeInDock),

            @"rememberPlaybackState": @NO,
            @"playbackWasPlaying": @NO,

            @"volume": @(0.75),
            @"stereoWidth": @0.0,
            @"stereoBalance": @0.0,
            
            @"togglePlaybackShortcut":  [Shortcut emptyShortcut],
            @"increaseVolumeShortcut":  [Shortcut emptyShortcut],
            @"decreaseVolumeShortcut":  [Shortcut emptyShortcut],
            
            @"enabledPresetIdentifiers": @[
                @"Default White",
                @"Default Pink",
                @"Default Brown"
            ],

            @"orderedPresetIdentifiers": @[
                @"Default White",
                @"Default Pink",
                @"Default Brown"
            ],
            
            @"selectedPresetIdentifier": @"Default White",
            
            @"autoMuteBundleIdentifiers": @[ ],
            @"muteForMusicApps":  @NO,
            @"muteForNowPlaying": @NO,

            // Hidden preferences
            @"useNowPlayingSPI":  @NO,
            @"playFadeDuration":  @0.1,
            @"pauseFadeDuration": @0.15,
            @"muteFadeDuration":  @1.0
        };
    });

    return sDefaultValues;
}


static void sSetDefaultObject(id dictionary, NSString *key, id valueToSave, id defaultValue)
{
    void (^saveObject)(NSObject *, NSString *) = ^(NSObject *o, NSString *k) {
        if (o) {
            [dictionary setObject:o forKey:k];
        } else {
            [dictionary removeObjectForKey:k];
        }
    };

    if (
        [defaultValue isKindOfClass:[NSNumber class]] ||
        [defaultValue isKindOfClass:[NSString class]] ||
        [defaultValue isKindOfClass:[NSArray  class]]
    ) {
        saveObject(valueToSave, key);

    } else if ([defaultValue isKindOfClass:[Shortcut class]]) {
        if (valueToSave == [Shortcut emptyShortcut]) {
            valueToSave = nil;
        }

        saveObject([valueToSave preferencesString], key);
    }
}


@implementation Settings


+ (void) registerDefaults
{
    static BOOL sDidRegisterDefaults = NO;
    if (sDidRegisterDefaults) return;

    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];

    NSDictionary *defaultValuesDictionary = sGetDefaultValues();
    for (NSString *key in defaultValuesDictionary) {
        id value = [defaultValuesDictionary objectForKey:key];
        sSetDefaultObject(defaults, key, value, value);
    }

    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    
    sDidRegisterDefaults = YES;
}


+ (id) sharedInstance
{
    static Settings *sSharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        [self registerDefaults];
        sSharedInstance = [[Settings alloc] init];
    });
    
    return sSharedInstance;
}


- (id) init
{
    if ((self = [super init])) {
        [self _load];
        
        for (NSString *key in sGetDefaultValues()) {
            [self addObserver:self forKeyPath:key options:0 context:NULL];
        }
    }

    return self;
}


- (void) _load
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSDictionary *defaultValuesDictionary = sGetDefaultValues();
    for (NSString *key in defaultValuesDictionary) {
        id defaultValue = [defaultValuesDictionary objectForKey:key];

        if ([defaultValue isKindOfClass:[NSNumber class]]) {
            id number = [defaults objectForKey:key];

            if ([number isKindOfClass:[NSNumber class]]) {
                [self setValue:number forKey:key];
            }

        } else if ([defaultValue isKindOfClass:[NSString class]]) {
            NSString *value = [defaults stringForKey:key];
            if (value) [self setValue:value forKey:key];

        } else if ([defaultValue isKindOfClass:[NSArray class]]) {
            NSArray *value = [defaults arrayForKey:key];

            for (id member in value) {
                if (![member isKindOfClass:[NSString class]]) {
                    value = nil;
                    break;
                }
            }

            if (value) [self setValue:value forKey:key];

        } else if ([defaultValue isKindOfClass:[Shortcut class]]) {
            NSString *preferencesString = [defaults objectForKey:key];
            Shortcut *shortcut          = nil;

            if ([preferencesString isKindOfClass:[NSString class]]) {
                shortcut = [Shortcut shortcutWithPreferencesString:preferencesString];
            }
            
            [self setValue:shortcut forKey:key];
        }
    }
}


- (void) _save
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSDictionary *defaultValuesDictionary = sGetDefaultValues();
    for (NSString *key in defaultValuesDictionary) {
        id defaultValue = [defaultValuesDictionary objectForKey:key];
        id selfValue    = [self valueForKey:key];
        
        sSetDefaultObject(defaults, key, selfValue, defaultValue);
    }

    [defaults synchronize];
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == self) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SettingsDidChangeNotificationName object:self];
        [self _save];
    }
}


@end
