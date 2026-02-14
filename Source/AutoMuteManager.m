// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "AutoMuteManager.h"
#import "Settings.h"

#include <dlfcn.h>

@import AppKit;
@import UniformTypeIdentifiers;

NSString * const AutoMuteDidChangeNotificationName = @"AutoMuteDidChangeNotification";


// MediaRemote SPI
static void (*MRMediaRemoteRegisterForNowPlayingNotifications)(dispatch_queue_t queue);
static void (*MRMediaRemoteGetAnyApplicationIsPlaying)(dispatch_queue_t queue, void (^callback)(BOOL playing));


static NSString *sAppleMusicBundleIdentifier = @"com.apple.Music";
static NSString *sAppleMusicPlayerInfoNotificationName = @"com.apple.Music.playerInfo";

static NSString *sSwinsianBundleIdentifier = @"com.swinsian.Swinsian";
static NSString *sSwinsianTrackPlayingNotificationName = @"com.swinsian.Swinsian-Track-Playing";
static NSString *sSwinsianTrackStoppedNotificationName = @"com.swinsian.Swinsian-Track-Stopped";
static NSString *sSwinsianTrackPausedNotificationName  = @"com.swinsian.Swinsian-Track-Paused";

static NSString *sSpotifyBundleIdentifier = @"com.spotify.client";
static NSString *sSpotifyPlaybackStateChangedNotificationName = @"com.spotify.client.PlaybackStateChanged";


static id sSharedInstance = nil;

typedef NS_ENUM(NSInteger, PlayerState) {
    PlayerStateUnknown = 0,
    PlayerStatePlaying = 1,
    PlayerStateNotPlaying = 2 // paused, stopped, or not running
};


@interface AutoMuteManagerEntry ()
@property (nonatomic) NSString *name;
@property (nonatomic) NSString *bundleIdentifier;
@property (nonatomic) NSImage *iconImage;
@end

@implementation AutoMuteManagerEntry
@end


@implementation AutoMuteManager {
    PlayerState _appleMusicPlayerState;
    PlayerState _swinsianPlayerState;
    PlayerState _spotifyPlayerState;
    BOOL _didSetupPlayerState;

    BOOL _nowPlayingIsActive;
    BOOL _didSetupNowPlaying;
}

+ (BOOL) isNowPlayingSPIEnabled
{
    BOOL isNowPlayingSPIEnabled = YES;
    
    if (![[Settings sharedInstance] useNowPlayingSPI]) {
        if (@available(macOS 15.4, *)) {
            isNowPlayingSPIEnabled = NO;
        }
    }

    return isNowPlayingSPIEnabled;
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
        [[NSWorkspace sharedWorkspace] addObserver:self forKeyPath:@"runningApplications" options:0 context:NULL];

        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(_handleSettingsDidChange:)
                                                     name: SettingsDidChangeNotificationName
                                                   object: nil];

        [self _registerForDistributedNotifications];

        NSMutableArray *entries = [NSMutableArray array];
        for (NSString *bundleIdentifier in [[Settings sharedInstance] autoMuteBundleIdentifiers]) {
            [entries addObject:[self _entryWithBundleIdentifier:bundleIdentifier]];
        }

        _entries = [self _sortedEntriesWithEntries:entries];

        [self _handleSettingsDidChange:nil];
        [self _setNeedsUpdate];
    }

    return self;
}


#pragma mark - Notifications / KVO

- (void) observeValueForKeyPath: (NSString *) keyPath
                       ofObject: (id) object
                         change: (NSDictionary *) change
                        context: (void *) context
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _setNeedsUpdate];
    });
}


- (void) _handleSettingsDidChange:(NSNotification *)note
{
    if ([[Settings sharedInstance] muteForMusicApps] && !_didSetupPlayerState) {
        [self _setupPlayerState];
    }

    if ([[Settings sharedInstance] muteForNowPlaying] && !_didSetupNowPlaying) {
        [self _setupNowPlayingSPI];
    }

    [self _setNeedsUpdate];
}


- (void) _handleAppleMusicNotification:(NSNotification *)note
{
    NSString *playerState = [[note userInfo] objectForKey:@"Player State"];
    if (!playerState) return;
    
    _appleMusicPlayerState = [playerState isEqualToString:@"Playing"] ?
        PlayerStatePlaying : PlayerStateNotPlaying;
    
    [self _setNeedsUpdate];
}


- (void) _handleSpotifyNotification:(NSNotification *)note
{
    NSString *playerState = [[note userInfo] objectForKey:@"Player State"];
    if (!playerState) return;

    _spotifyPlayerState = [playerState isEqualToString:@"Playing"] ?
        PlayerStatePlaying : PlayerStateNotPlaying;
    
    [self _setNeedsUpdate];
}


- (void) _handleSwinsianNotification:(NSNotification *)note
{
    NSString *name = [note name];

    if ([name isEqualToString:sSwinsianTrackPlayingNotificationName]) {
        _swinsianPlayerState = PlayerStatePlaying;
    } else if ([name isEqualToString:sSwinsianTrackPausedNotificationName]) {
        _swinsianPlayerState = PlayerStateNotPlaying;
    } else if ([name isEqualToString:sSwinsianTrackStoppedNotificationName]) {
        _swinsianPlayerState = PlayerStateNotPlaying;
    }

    [self _setNeedsUpdate];
}


- (void) _registerForDistributedNotifications
{
    __auto_type observe = ^(id observer, SEL aSelector, NSString *notificationName) {
        [[NSDistributedNotificationCenter defaultCenter] addObserver: observer
                                                            selector: aSelector
                                                                name: notificationName
                                                              object: nil];
    };

    observe( self, @selector(_handleAppleMusicNotification:), sAppleMusicPlayerInfoNotificationName );

    observe( self, @selector(_handleSpotifyNotification:),    sSpotifyPlaybackStateChangedNotificationName );

    observe( self, @selector(_handleSwinsianNotification:),   sSwinsianTrackPlayingNotificationName );
    observe( self, @selector(_handleSwinsianNotification:),   sSwinsianTrackPausedNotificationName  );
    observe( self, @selector(_handleSwinsianNotification:),   sSwinsianTrackStoppedNotificationName );
}


- (void) _handleNowPlayingNotification:(NSNotification *)note
{
    if (!MRMediaRemoteGetAnyApplicationIsPlaying) return;
        
    __weak id weakSelf = self;
    
    MRMediaRemoteGetAnyApplicationIsPlaying(dispatch_get_main_queue(), ^(BOOL yn) {
        [weakSelf _updateNowPlayingIsActive:yn];
    });
}


#pragma mark - Private Methods

- (void) _setupPlayerState
{
    __auto_type runScript = ^(NSString *scriptName) {
        NSURL *scriptURL = [[NSBundle mainBundle] URLForResource:scriptName withExtension:@"scpt"];
        if (!scriptURL) return NO;
        
        NSDictionary *errorInfo = nil;
        
        NSAppleScript *script = [[NSAppleScript alloc] initWithContentsOfURL:scriptURL error:&errorInfo];
        if (!script) return NO;
        
        NSAppleEventDescriptor *descriptor = [script executeAndReturnError:&errorInfo];
        if (!descriptor) return NO;

        return (BOOL)([descriptor booleanValue] > 0);
    };

    if (_appleMusicPlayerState == PlayerStateUnknown) {
        if (runScript(@"IsAppleMusicPlaying")) {
            _appleMusicPlayerState = PlayerStatePlaying;
        }
    }

    if (_spotifyPlayerState == PlayerStateUnknown) {
        if (runScript(@"IsSpotifyPlaying")) {
            _spotifyPlayerState = PlayerStatePlaying;
        }
    }

    if (_swinsianPlayerState == PlayerStateUnknown) {
        if (runScript(@"IsSwinsianPlaying")) {
            _swinsianPlayerState = PlayerStatePlaying;
        }
    }

    _didSetupPlayerState = YES;
}


- (void) _setupNowPlayingSPI
{
    if (_didSetupNowPlaying) return;

    if (![AutoMuteManager isNowPlayingSPIEnabled]) return;
    
    void *mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mediaRemote) return;

    MRMediaRemoteRegisterForNowPlayingNotifications = dlsym(mediaRemote, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!MRMediaRemoteRegisterForNowPlayingNotifications) return;

    MRMediaRemoteGetAnyApplicationIsPlaying  = dlsym(mediaRemote, "MRMediaRemoteGetAnyApplicationIsPlaying");
    if (!MRMediaRemoteGetAnyApplicationIsPlaying) return;

    void *hasMRMediaRemotePlayerIsPlayingDidChangeNotification = dlsym(mediaRemote, "kMRMediaRemotePlayerIsPlayingDidChangeNotification");
    if (!hasMRMediaRemotePlayerIsPlayingDidChangeNotification) return;

	MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());

    NSString *notificationName = @"kMRMediaRemotePlayerIsPlayingDidChangeNotification";

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_handleNowPlayingNotification:)
                                                 name: notificationName
                                               object: nil];

    [self _handleNowPlayingNotification:nil];

    _didSetupNowPlaying = YES;
}


- (void) _updateNowPlayingIsActive:(BOOL)yn
{
    _nowPlayingIsActive = yn;
    [self _update];
}


- (NSArray *) _sortedEntriesWithEntries:(NSArray<AutoMuteManagerEntry *> *)entries
{
    return [entries sortedArrayUsingComparator:^(id obj1, id obj2) {
        AutoMuteManagerEntry *entry1 = (AutoMuteManagerEntry *)obj1;
        AutoMuteManagerEntry *entry2 = (AutoMuteManagerEntry *)obj2;
        
        NSString *name1 = [[entry1 name] lowercaseString];
        NSString *name2 = [[entry2 name] lowercaseString];

        return [name1 compare:name2];
    }];
}


- (void) _setNeedsUpdate
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_update) object:nil];
    [self performSelector:@selector(_update) withObject:nil afterDelay:0.05];
}


- (void) _update
{
    BOOL shouldMute = NO;

    /*
        +[NSRunningApplication runningApplicationsWithBundleIdentifier:]
        is unreliable and can fail when other processes are being terminated.
        This appears to be a race condition in LaunchServices or some kind of XPC issue.

        To work around this: use -[NSWorkspace runningApplications] instead.
        While I haven't seen this behavior with -runningApplications, check
        for an empty array and re-call ourselves if needed.
    */
    NSArray *runningApplications = [[NSWorkspace sharedWorkspace] runningApplications];

    if (![runningApplications count]) {
        [self _setNeedsUpdate];
        return;
    }

    NSMutableSet *runningBundleIdentifiers = [NSMutableSet set];

    for (NSRunningApplication *application in runningApplications) {
        NSString *bundleIdentifier = [application bundleIdentifier];

        if (bundleIdentifier && ![application isTerminated]) {
            [runningBundleIdentifiers addObject:bundleIdentifier];
        }
    }

    // Check Now Playing
    {
        if (!shouldMute && [[Settings sharedInstance] muteForNowPlaying]) {
            if (_nowPlayingIsActive) {
                shouldMute = YES;
            }
        }
    }

    // Check music apps
    {
        if (!shouldMute && [[Settings sharedInstance] muteForMusicApps]) {
            if (![runningBundleIdentifiers containsObject:sAppleMusicBundleIdentifier]) {
                _appleMusicPlayerState = PlayerStateNotPlaying;
            }

            if (![runningBundleIdentifiers containsObject:sSpotifyBundleIdentifier]) {
                _spotifyPlayerState = PlayerStateNotPlaying;
            }

            if (![runningBundleIdentifiers containsObject:sSwinsianBundleIdentifier]) {
                _swinsianPlayerState = PlayerStateNotPlaying;
            }

            if (
                (_appleMusicPlayerState == PlayerStatePlaying) ||
                (_swinsianPlayerState   == PlayerStatePlaying) ||
                (_spotifyPlayerState    == PlayerStatePlaying)
            ) {
                shouldMute = YES;
            }
        }
    }

    // Check Entries
    {
        if (!shouldMute) {
            for (AutoMuteManagerEntry *entry in _entries) {
                if ([runningBundleIdentifiers containsObject:[entry bundleIdentifier]]) {
                    shouldMute = YES;
                    break;
                }
            }
        }
    }

    if (_shouldMute != shouldMute) {
        _shouldMute = shouldMute;
        [[NSNotificationCenter defaultCenter] postNotificationName:AutoMuteDidChangeNotificationName object:nil];
    }
}


#pragma mark - Entries

- (AutoMuteManagerEntry *) _entryWithBundleIdentifier:(NSString *)bundleIdentifier
{
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];

    NSURL    *URL = [workspace URLForApplicationWithBundleIdentifier:bundleIdentifier];
    NSString *name;
    NSImage  *icon;

    if (URL) {
        icon = [workspace iconForFile:[URL path]];

        NSBundle *bundle = [NSBundle bundleWithURL:URL];

        name = [[bundle localizedInfoDictionary] objectForKey:@"CFBundleDisplayName"];
        if (!name) name = [[bundle infoDictionary] objectForKey:@"CFBundleDisplayName"];
        if (!name) name = [[bundle localizedInfoDictionary] objectForKey:@"CFBundleName"];
        if (!name) name = [[bundle infoDictionary] objectForKey:@"CFBundleName"];
        if (!name) name = bundleIdentifier;

    } else {
        icon = [workspace iconForContentType:UTTypeApplicationBundle];
        name = bundleIdentifier;
    }

    AutoMuteManagerEntry *entry = [[AutoMuteManagerEntry alloc] init];
    
    [entry setBundleIdentifier:bundleIdentifier];
    [entry setName:name];
    [entry setIconImage:icon];

    return entry;
}


- (AutoMuteManagerEntry *) _existingEntryWithBundleIdentifier:(NSString *)bundleIdentifier
{
    for (AutoMuteManagerEntry *entry in _entries) {
        if ([[entry bundleIdentifier] isEqualToString:bundleIdentifier]) {
            return entry;
        }
    }
    
    return nil;
}


- (void) addEntryWithBundleIdentifier:(NSString *)bundleIdentifier
{
    if (!bundleIdentifier) return;

    if ([self _existingEntryWithBundleIdentifier:bundleIdentifier]) {
        return;
    }
   
    AutoMuteManagerEntry *entry = [self _entryWithBundleIdentifier:bundleIdentifier];
    if (!entry) return;

    NSMutableArray *entries = [_entries mutableCopy];
    [entries addObject:entry];
    [self setEntries:entries];
}


- (void) removeEntryWithBundleIdentifier:(NSString *)bundleIdentifier
{
    AutoMuteManagerEntry *entry = [self _existingEntryWithBundleIdentifier:bundleIdentifier];
    if (!entry) return;

    NSMutableArray *entries = [_entries mutableCopy];
    [entries removeObject:entry];
    [self setEntries:entries];
}


- (void) setEntries:(NSArray<AutoMuteManagerEntry *> *)entries
{
    if (_entries != entries) {
        _entries = [self _sortedEntriesWithEntries:entries];
        
        NSMutableArray *bundleIdentifiers = [NSMutableArray array];
        for (AutoMuteManagerEntry *entry in _entries) {
            [bundleIdentifiers addObject:[entry bundleIdentifier]];
        }
        
        [[Settings sharedInstance] setAutoMuteBundleIdentifiers:bundleIdentifiers];
        
        [self _setNeedsUpdate];
    }
}


@end
