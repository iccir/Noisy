// (c) 2011-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "Shortcut.h"

@import Carbon;
@import AppKit;


@interface Shortcut ()
@end


static CFStringRef  sNumericPadMarker   = CFSTR("<<<PAD>>>");
static CFStringRef *sKeyCodeToStringMap = nil;


@implementation Shortcut

+ (void) initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sKeyCodeToStringMap = (CFStringRef *)calloc(128, sizeof(CFStringRef));

        sKeyCodeToStringMap[36]  = CFSTR( "\u21A9" );
        sKeyCodeToStringMap[48]  = CFSTR( "\u21E5" );
        sKeyCodeToStringMap[49]  = CFSTR( "Space"  );
        sKeyCodeToStringMap[51]  = CFSTR( "\u232B" );
        sKeyCodeToStringMap[53]  = CFSTR( "\u238B" );
        sKeyCodeToStringMap[64]  = CFSTR( "F17"    );
        sKeyCodeToStringMap[71]  = CFSTR( "\u2327" );
        sKeyCodeToStringMap[76]  = CFSTR( "\u2305" );
        sKeyCodeToStringMap[79]  = CFSTR( "F18"    );
        sKeyCodeToStringMap[80]  = CFSTR( "F19"    );
        sKeyCodeToStringMap[96]  = CFSTR( "F5"     );
        sKeyCodeToStringMap[97]  = CFSTR( "F6"     );
        sKeyCodeToStringMap[98]  = CFSTR( "F7"     );
        sKeyCodeToStringMap[99]  = CFSTR( "F3"     );
        sKeyCodeToStringMap[65]  = sNumericPadMarker;
        sKeyCodeToStringMap[67]  = sNumericPadMarker;
        sKeyCodeToStringMap[69]  = sNumericPadMarker;
        sKeyCodeToStringMap[75]  = sNumericPadMarker;
        sKeyCodeToStringMap[78]  = sNumericPadMarker;
        sKeyCodeToStringMap[81]  = sNumericPadMarker;
        sKeyCodeToStringMap[82]  = sNumericPadMarker;
        sKeyCodeToStringMap[83]  = sNumericPadMarker;
        sKeyCodeToStringMap[84]  = sNumericPadMarker;
        sKeyCodeToStringMap[85]  = sNumericPadMarker;
        sKeyCodeToStringMap[86]  = sNumericPadMarker;
        sKeyCodeToStringMap[87]  = sNumericPadMarker;
        sKeyCodeToStringMap[88]  = sNumericPadMarker;
        sKeyCodeToStringMap[89]  = sNumericPadMarker;
        sKeyCodeToStringMap[91]  = sNumericPadMarker;
        sKeyCodeToStringMap[92]  = sNumericPadMarker;
        sKeyCodeToStringMap[100] = CFSTR( "F8"     );
        sKeyCodeToStringMap[101] = CFSTR( "F9"     );
        sKeyCodeToStringMap[103] = CFSTR( "F11"    );
        sKeyCodeToStringMap[105] = CFSTR( "F13"    );
        sKeyCodeToStringMap[106] = CFSTR( "F16"    );
        sKeyCodeToStringMap[107] = CFSTR( "F14"    );
        sKeyCodeToStringMap[109] = CFSTR( "F10"    );
        sKeyCodeToStringMap[111] = CFSTR( "F12"    );
        sKeyCodeToStringMap[113] = CFSTR( "F15"    );
        sKeyCodeToStringMap[114] = CFSTR( "\x3F"   );
        sKeyCodeToStringMap[115] = CFSTR( "\u2196" );
        sKeyCodeToStringMap[116] = CFSTR( "\u21DE" );
        sKeyCodeToStringMap[117] = CFSTR( "\u2326" );
        sKeyCodeToStringMap[118] = CFSTR( "F4"     );
        sKeyCodeToStringMap[119] = CFSTR( "\u2198" );
        sKeyCodeToStringMap[120] = CFSTR( "F2"     );
        sKeyCodeToStringMap[121] = CFSTR( "\u21DF" );
        sKeyCodeToStringMap[122] = CFSTR( "F1"     );
        sKeyCodeToStringMap[123] = CFSTR( "\u2190" );
        sKeyCodeToStringMap[124] = CFSTR( "\u2192" );
        sKeyCodeToStringMap[125] = CFSTR( "\u2193" );
        sKeyCodeToStringMap[126] = CFSTR( "\u2191" );
    });
}


+ (Shortcut *) shortcutWithPreferencesString:(NSString *)string
{
    return [[self alloc] initWithPreferencesString:string];
}


+ (Shortcut *) emptyShortcut
{
    static Shortcut *sEmptyShortcut = nil;
    if (!sEmptyShortcut) sEmptyShortcut = [[self alloc] initWithKeyCode:UINT16_MAX modifierFlags:0];
    return sEmptyShortcut;
}


+ (Shortcut *) shortcutWithWithKeyCode:(unsigned short)keycode modifierFlags:(NSUInteger)modifierFlags
{
    return [[self alloc] initWithKeyCode:keycode modifierFlags:modifierFlags];
}


+ (NSString *) stringForModifierFlags:(NSUInteger)modifierFlags
{
    NSMutableString *result = [NSMutableString stringWithCapacity:4];
    
    if (modifierFlags & NSEventModifierFlagControl)  [result appendFormat:@"%C", (unsigned short)kControlUnicode];
    if (modifierFlags & NSEventModifierFlagOption)   [result appendFormat:@"%C", (unsigned short)kOptionUnicode];
    if (modifierFlags & NSEventModifierFlagShift)    [result appendFormat:@"%C", (unsigned short)kShiftUnicode];
    if (modifierFlags & NSEventModifierFlagCommand)  [result appendFormat:@"%C", (unsigned short)kCommandUnicode];

    return result;
}


+ (NSString *) stringForKeyCode:(unsigned short)keyCode
{
    BOOL isNumericPad = NO;
    CFStringRef mapLookup = nil;

    if ((keyCode >= 0) && (keyCode < 128)) {
        mapLookup = sKeyCodeToStringMap[keyCode];

        if (mapLookup == sNumericPadMarker) {
            mapLookup = nil;
            isNumericPad = YES;
        } 
        
        if (mapLookup) {
            return (__bridge NSString *)mapLookup;
        }
    }

    TISInputSourceRef tisSource = TISCopyCurrentKeyboardInputSource();
	if (!tisSource) return nil;

	UInt32 keysDown = 0;
	CFDataRef layoutData = (CFDataRef)TISGetInputSourceProperty(tisSource, kTISPropertyUnicodeKeyLayoutData);
	if (!layoutData) return nil;

	const UCKeyboardLayout *keyLayout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
			
	UniCharCount length = 4, realLength;
	UniChar characters[4];
    NSString *result = nil;

	if (noErr == UCKeyTranslate(keyLayout, keyCode, kUCKeyActionDisplay, 0, LMGetKbdType(), kUCKeyTranslateNoDeadKeysBit, &keysDown, length, &realLength, characters)) {
        result = [[NSString stringWithCharacters:characters length:1] uppercaseString];

        if (isNumericPad) {
            result = [NSString stringWithFormat:@"[%@]", result];
        }
    }


    if (tisSource) CFRelease(tisSource);
    
    return result;
}


#pragma mark - Lifecycle

- (id) initWithKeyCode:(unsigned short)keyCode modifierFlags:(NSUInteger)modifierFlags
{
    if ((self = [super init])) {
        _keyCode       = keyCode;
        _modifierFlags = modifierFlags;
    }

    return self;
}


- (id) initWithPreferencesString:(NSString *)string
{
    NSUInteger   modifierFlags = 0;
    NSUInteger   datum         = 0;

    NSArray *components = [string componentsSeparatedByString:@","];
    
    if ([components count] >= 3) {
        NSString *modifierString = [components objectAtIndex:1];
        NSString *datumString    = [components objectAtIndex:2];

        if ([modifierString rangeOfString:@"^"].location != NSNotFound) {
            modifierFlags |= NSEventModifierFlagControl;
        }
        
        if ([modifierString rangeOfString:@"~"].location != NSNotFound) {
            modifierFlags |= NSEventModifierFlagOption;
        }

        if ([modifierString rangeOfString:@"$"].location != NSNotFound) {
            modifierFlags |= NSEventModifierFlagShift;
        }

        if ([modifierString rangeOfString:@"@"].location != NSNotFound) {
            modifierFlags |= NSEventModifierFlagCommand;
        }

        if ([modifierString rangeOfString:@"F"].location != NSNotFound) {
            modifierFlags |= NSEventModifierFlagFunction;
        }

        const char *cString = [datumString cStringUsingEncoding:NSUTF8StringEncoding];
        sscanf(cString, "%04lx", &datum);
    }

    return [self initWithKeyCode:datum modifierFlags:modifierFlags];
}


- (id) init
{
    return nil;
}


- (id) copyWithZone:(NSZone *)zone
{
    return self;
}


- (BOOL) isEqual:(id)anotherObject
{
    if (anotherObject == self) return YES;

    if ([anotherObject isKindOfClass:[Shortcut class]]) {
        Shortcut *anotherShortcut = (Shortcut *)anotherObject;

        return anotherShortcut->_modifierFlags == _modifierFlags &&
               anotherShortcut->_keyCode       == _keyCode;
    }

    return NO;
}


- (NSUInteger) hash
{
    return [self shortcutID];
}


#pragma mark - Accessors

- (NSUInteger) shortcutID
{
    NSUInteger shortcutID = 0;

    if (_modifierFlags & NSEventModifierFlagControl)  shortcutID |= 0x10000;
    if (_modifierFlags & NSEventModifierFlagCommand)  shortcutID |= 0x20000;
    if (_modifierFlags & NSEventModifierFlagShift  )  shortcutID |= 0x40000;
    if (_modifierFlags & NSEventModifierFlagOption )  shortcutID |= 0x80000;

    shortcutID |= _keyCode;
    
    return shortcutID;
}


- (NSString *) preferencesString
{
    NSMutableString *result = [NSMutableString string];

    [result appendString:@"key,"];

    if (_modifierFlags & NSEventModifierFlagControl)   [result appendString:@"^"];
    if (_modifierFlags & NSEventModifierFlagOption)    [result appendString:@"~"];
    if (_modifierFlags & NSEventModifierFlagShift)     [result appendString:@"$"];
    if (_modifierFlags & NSEventModifierFlagCommand)   [result appendString:@"@"];
    if (_modifierFlags & NSEventModifierFlagFunction)  [result appendString:@"F"];
    if (_modifierFlags == 0)                           [result appendString:@"_"];

    [result appendFormat:@",%04lx", (long)_keyCode];
    
    return result;
}


- (NSString *) displayString
{
    NSString *modifierString = [Shortcut stringForModifierFlags:_modifierFlags];
    NSString *keyCodeString  = [Shortcut stringForKeyCode:_keyCode];

    return [NSString stringWithFormat:@"%@%@", modifierString, keyCodeString];
}

@end
