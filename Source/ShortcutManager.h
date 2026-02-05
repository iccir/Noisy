// (c) 2011-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

@protocol ShortcutListener;

@class Shortcut;
@class ShortcutView;

@interface ShortcutManager : NSObject

+ (BOOL) hasSharedInstance;
+ (id) sharedInstance;

- (void) addListener:(id<ShortcutListener>)listener;
- (void) removeListener:(id<ShortcutListener>)listener;

@property (nonatomic, copy) NSArray<Shortcut *> *shortcuts;

@end


@protocol ShortcutListener <NSObject>
- (BOOL) performShortcut:(Shortcut *)shortcut;
@end
