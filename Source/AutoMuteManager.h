// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

extern NSString * const AutoMuteDidChangeNotificationName;

@interface AutoMuteManagerEntry : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSImage  *iconImage;
@end


@interface AutoMuteManager : NSObject

+ (BOOL) isNowPlayingSPIEnabled;

+ (id) sharedInstance;

- (void) addEntryWithBundleIdentifier:(NSString *)bundleIdentifier;
- (void) removeEntryWithBundleIdentifier:(NSString *)bundleIdentifier;

@property (nonatomic) NSArray<AutoMuteManagerEntry *> *entries;

@property (nonatomic, readonly) BOOL shouldMute;

@end

