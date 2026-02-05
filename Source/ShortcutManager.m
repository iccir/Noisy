// (c) 2011-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "ShortcutManager.h"
#import "Shortcut.h"

@import Carbon;
@import AppKit;

static id sSharedInstance = nil;

@interface ShortcutManager ()
@property (nonatomic, strong) NSHashTable *listeners;
@property (nonatomic, strong) NSMutableDictionary *shortcutIDToRefMap;
@property (nonatomic, strong) NSMutableDictionary *shortcutIDToShortcutMap;
@end


@implementation ShortcutManager

+ (BOOL) hasSharedInstance
{
    return (sSharedInstance != nil);
}


+ (id) sharedInstance
{
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sSharedInstance = [[self alloc] init];

		EventTypeSpec eventSpec = { kEventClassKeyboard, kEventHotKeyPressed };
		InstallApplicationEventHandler(&sHandleEvent, 1, &eventSpec, (__bridge void *)sSharedInstance, NULL);
    });

    return sSharedInstance;
}


#pragma mark - Lifecycle

- (id) init
{
    if ((self = [super init])) {
        _listeners               = [NSHashTable weakObjectsHashTable];
        _shortcutIDToRefMap      = [[NSMutableDictionary alloc] init];
        _shortcutIDToShortcutMap = [[NSMutableDictionary alloc] init];
    }

    return self;
}


- (void) dealloc
{
    for (Shortcut *shortcut in _shortcuts) {
        [self _unregisterShortcut:shortcut];
    }
}


#pragma mark - Private Methods

- (BOOL) _handleHotKeyID:(NSUInteger)keyID
{
    NSNumber *keyIDAsNumber = [[NSNumber alloc] initWithUnsignedInteger:keyID];

    Shortcut *shortcut = [_shortcutIDToShortcutMap objectForKey:keyIDAsNumber];
    BOOL yn = NO;

    if (shortcut) {
        for (id<ShortcutListener> listener in _listeners) {
            yn = yn || [listener performShortcut:shortcut];
        }
    }

    return yn;
}


static OSStatus sHandleEvent(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData)
{
	@autoreleasepool {
		EventHotKeyID hotKeyID = { 0, 0 };

		if (noErr == GetEventParameter(inEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID)) {
        	[(__bridge ShortcutManager *)inUserData _handleHotKeyID:(NSUInteger)hotKeyID.id];
    	}
    }

    return noErr;
}


- (void) _unregisterShortcutIDAsNumber:(NSNumber *)key
{
    EventHotKeyRef hotKeyRef = [[_shortcutIDToRefMap objectForKey:key] pointerValue];
    if (hotKeyRef) UnregisterEventHotKey(hotKeyRef);

    [_shortcutIDToRefMap      removeObjectForKey:key];
    [_shortcutIDToShortcutMap removeObjectForKey:key];
}


- (void) _unregisterShortcut:(Shortcut *)shortcut
{
    NSUInteger shortcutID = [shortcut shortcutID];

    NSNumber *shortcutIDAsNumber = [[NSNumber alloc] initWithUnsignedInteger:shortcutID];
    [self _unregisterShortcutIDAsNumber:shortcutIDAsNumber];
}


- (void) _registerShortcut:(Shortcut *)shortcut
{
    NSUInteger     shortcutID    = [shortcut shortcutID];
    unsigned short keyCode       = [shortcut keyCode];
    NSUInteger     modifierFlags = [shortcut modifierFlags];

    EventHotKeyID  eventKeyID   = { 'htk1', (UInt32)shortcutID };
	EventHotKeyRef hotKeyRef    = NULL;

    NSNumber *shortcutIDAsNumber = [[NSNumber alloc] initWithUnsignedInteger:shortcutID];
    [self _unregisterShortcutIDAsNumber:shortcutIDAsNumber];

    UInt32 flags = 0;
    if (modifierFlags & NSEventModifierFlagControl  )  flags |= controlKey;
    if (modifierFlags & NSEventModifierFlagCommand  )  flags |= cmdKey;
    if (modifierFlags & NSEventModifierFlagShift    )  flags |= shiftKey;
    if (modifierFlags & NSEventModifierFlagOption   )  flags |= optionKey;

	if (RegisterEventHotKey(keyCode, flags, eventKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef) == noErr) {
        [_shortcutIDToRefMap setObject:[NSValue valueWithPointer:hotKeyRef] forKey:shortcutIDAsNumber];
        [_shortcutIDToShortcutMap setObject:shortcut forKey:shortcutIDAsNumber];
    }

}


#pragma mark - Public Methods

- (void) addListener:(id<ShortcutListener>)listener
{
    [_listeners addObject:listener];
}


- (void) removeListener:(id<ShortcutListener>)listener
{
    [_listeners removeObject:listener];
}


#pragma mark - Accessors

- (void) setShortcuts:(NSArray *)shortcuts
{
    if (shortcuts && [_shortcuts isEqual:shortcuts]) {
        return;
    }

    // Add new shortcuts
    for (Shortcut *shortcut in shortcuts) {
        if (![_shortcuts containsObject:shortcut]) {
            [self _registerShortcut:shortcut];
        }
    }
    
    // Delete old shortcuts
    for (Shortcut *shortcut in _shortcuts) {
        if (![shortcuts containsObject:shortcut]) {
            [self _unregisterShortcut:shortcut];
        }
    }
    
    _shortcuts = [shortcuts copy];
}

@end
