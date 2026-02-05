// (c) 2024-2026 Ricci Adams
// MIT License (or) 1-clause BSD License


@import Foundation;

@interface Preset : NSObject

+ (NSString *) identifierWithFileURL:(NSURL *)fileURL;

- (instancetype) initWithFileURL:(NSURL *)fileURL enabled:(BOOL)enabled;

- (void) updateWithModificationDate:(NSDate *)modificationDate;

@property (nonatomic, readonly) NSURL *fileURL;
@property (nonatomic, readonly) NSDate *modificationDate;

// Returns the file name without an extension
@property (nonatomic, readonly) NSString *identifier;

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSDictionary *rootDictionary;
@property (nonatomic, readonly) NSError *error;

@property (nonatomic, getter=isEnabled) BOOL enabled;


@end
