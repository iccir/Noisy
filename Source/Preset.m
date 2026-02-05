// (c) 2024-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "Preset.h"
#import "Biquad.h"
#import "PresetManager.h"


@interface PresetManager (FriendMethods)
- (void) updateEnabledPresets;
@end


@implementation Preset

+ (NSString *) identifierWithFileURL:(NSURL *)fileURL
{
    return [[fileURL lastPathComponent] stringByDeletingPathExtension];
}

- (NSString *) description
{
    return [self identifier];
}

- (instancetype) initWithFileURL:(NSURL *)fileURL enabled:(BOOL)enabled
{
    if ((self = [super init])) {
        _fileURL = fileURL;
        _identifier = [Preset identifierWithFileURL:fileURL];
        _modificationDate = [NSDate distantPast];
        _enabled = enabled;
    }
    
    return self;
}


- (void) _readFile
{
    __block NSError *error = nil;

    __auto_type makeError = ^(NSString *description) {
        return [NSError errorWithDomain:@"NoisyErrorDomain" code:0 userInfo:@{
            NSLocalizedDescriptionKey: description
        }];
    };

    __auto_type getString = ^(NSDictionary *dictionary, NSString *key) {
        id value = [dictionary objectForKey:key];
        return [value isKindOfClass:[NSString class]] ? value : nil;
    };

    NSData *data = [NSData dataWithContentsOfURL:_fileURL options:0 error:&error];
    NSDictionary *rootDictionary;
    
    if (data && !error) {
        NSJSONReadingOptions options = NSJSONReadingJSON5Allowed;
        rootDictionary = [NSJSONSerialization JSONObjectWithData:data options:options error:&error];
        if (!error && ![rootDictionary isKindOfClass:[NSDictionary class]]) {
            error = makeError(@"Root must be an object type.");
            rootDictionary = nil;
        }
    }
    
    NSString *name = getString(rootDictionary, @"name");
   
    if (!name) {
        name = _identifier;
    }

    _name = name;
    _rootDictionary = rootDictionary;
    _error = error;
}


- (void) updateWithModificationDate:(NSDate *)modificationDate
{
    _modificationDate = modificationDate;
    [self _readFile];
}


- (void) setEnabled:(BOOL)enabled
{
    if (_enabled != enabled) {
        _enabled = enabled;
        [[PresetManager sharedInstance] updateEnabledPresets];
    }
}

@end
