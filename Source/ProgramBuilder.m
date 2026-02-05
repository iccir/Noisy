// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "ProgramBuilder.h"

#import "NoisyNode.h"
#import "NoisyProgram.h"
#import "Biquad.h"
#import "Preset.h"

static id sRequired = @{};

NSErrorDomain ProgramBuilderErrorDomain = @"ProgramBuilderErrorDomain";


@implementation ProgramBuilder {
    NSError *_error;
    NSMutableArray *_pathComponents;
    NSInteger _autoGainRandomSeed;
    NSInteger _nodeDepth;

    NoisyNodeList *_headNodeList;
    NoisyNodeList *_leftNodeList;
    NoisyNodeList *_rightNodeList;
}


#pragma mark - Lifecycle

- (instancetype) initWithPreset: (Preset *) preset
                   channelCount: (size_t) channelCount
                     sampleRate: (double) sampleRate
                    forAutoGain: (BOOL) forAutoGain
{
    if ((self = [super init])) {
        _preset = preset;
        _channelCount = channelCount;
        _sampleRate = sampleRate;
        _forAutoGain = forAutoGain;
        
        _pathComponents = [NSMutableArray array];
        
        [self _parsePreset];
    }

    return self;
}


- (void) dealloc
{
    NoisyNodeFree(_headNodeList);
    NoisyNodeFree(_leftNodeList);
    NoisyNodeFree(_rightNodeList);
}

#pragma mark - Validation

- (void) _pushPathComponent:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2)
{
    va_list v;
    va_start(v, format);

    NSString *string = [[NSString alloc] initWithFormat:format arguments:v];
    [_pathComponents addObject:string];

    va_end(v);
}

- (void) _popPathComponent
{
    [_pathComponents removeLastObject];
}


- (BOOL) _assertClass:(Class)cls ofObject:(id)object
{
    if ([object isKindOfClass:cls]) return YES;

    NSString *expectedType;
    NSString *actualType;
    
    if      ([cls isEqual:[NSDictionary class]])           { expectedType = @"object";  }
    else if ([cls isEqual:[NSArray class]])                { expectedType = @"array";   }
    else if ([cls isEqual:[NSNumber class]])               { expectedType = @"number";  }
    else if ([cls isEqual:[NSString class]])               { expectedType = @"string";  }
    else                                                   { expectedType = @"???";     }

    if      ([object isKindOfClass:[NSDictionary class]])  { actualType = @"object";    }
    else if ([object isKindOfClass:[NSArray class]])       { actualType = @"array";     }
    else if ([object isKindOfClass:[NSNumber class]])      { actualType = @"number";    }
    else if ([object isKindOfClass:[NSString class]])      { actualType = @"string";    }
    else                                                   { actualType = @"???";       }

    [self _raiseError:@"Expected %@ type instead of %@ type", expectedType, actualType];
    
    return NO;
}


- (void) _raiseError:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2)
{
    va_list v;
    va_start(v, format);

    if (!_error) {
        NSString *errorString = [[NSString alloc] initWithFormat:format arguments:v];

        NSString *localizedDescription = [NSString stringWithFormat:@"Error loading '%@'",
            [[_preset fileURL] lastPathComponent]];

        NSString *debugDescription = [NSString stringWithFormat:@"%@\n\nJSON Path: '%@'",
            errorString,
            [_pathComponents componentsJoinedByString:@""]];

        NSError *error = [NSError errorWithDomain:ProgramBuilderErrorDomain code:-1000 userInfo:@{
            NSLocalizedDescriptionKey: localizedDescription,
            NSDebugDescriptionErrorKey: debugDescription
        }];

        _error = error;
    }
    
    va_end(v);
}


- (NSDictionary *) _validateDictionary:(NSDictionary *)inDictionary withTemplate:(NSDictionary *)template
{
    NSMutableDictionary *outDictionary = [NSMutableDictionary dictionary];

    for (NSString *key in template) {
        NSArray *templateValue = [template objectForKey:key];

        Class expectedClass = [templateValue objectAtIndex:0];
        id    defaultValue  = [templateValue count] > 1 ? [templateValue lastObject] : nil;

        id value = [inDictionary objectForKey:key];

        if ([value isKindOfClass:expectedClass]) {
            [outDictionary setObject:value forKey:key];

        } else {
            if (!value) {
                if (defaultValue == sRequired) {
                    [self _raiseError:@"Missing required key: '%@'", key];
                } else if (defaultValue) {
                    [outDictionary setObject:defaultValue forKey:key];
                }
            } else {
                [self _pushPathComponent:@".%@", key];
                [self _assertClass:expectedClass ofObject:value];
                [self _popPathComponent];
            }
        
        }
    }

    // Check for superfluous keys
    for (NSString *key in inDictionary) {
        if (![template objectForKey:key]) {
            [self _raiseError:@"Unknown key: '%@'", key];
        }
    }

    return outDictionary;
}


- (id) _validateEnumKey:(NSString *)key inDictionary:(NSDictionary *)inDictionary withMap:(NSDictionary *)map
{
    id inValue = [inDictionary objectForKey:key];
    id outValue = [map objectForKey:inValue];
    
    if (!outValue) {
        [self _pushPathComponent:@".%@", key];
        [self _raiseError:@"Unknown value: '%@'", inValue];
        [self _popPathComponent];
    }
    
    return outValue;
}


#pragma mark - Readers

- (void) _readAutoGainSettings:(NSDictionary *)inNode
{
    inNode = [self _validateDictionary:inNode withTemplate:@{
        @"level":    @[ [NSNumber class], @( -3.0 ) ],
        @"separate": @[ [NSNumber class], @NO       ],
    }];
        
    _autoGainLevel    = [[inNode objectForKey:@"level"] doubleValue];
    _autoGainSeparate = [[inNode objectForKey:@"separate"] boolValue];
}


- (Biquad *) _readBiquad:(NSDictionary *)inNode
{
    inNode = [self _validateDictionary:inNode withTemplate:@{
        @"type":      @[ [NSString class], sRequired ],
        @"frequency": @[ [NSNumber class], sRequired ],
        @"gain":      @[ [NSNumber class], @0 ],
        @"Q":         @[ [NSNumber class], @( M_SQRT1_2 ) ],
    }];

    if (_error) return nil;

    double frequency     = [[inNode objectForKey:@"frequency"] doubleValue];
    double gain          = [[inNode objectForKey:@"gain"]      doubleValue];
    double Q             = [[inNode objectForKey:@"Q"]         doubleValue];

    NSNumber *typeNumber = [self _validateEnumKey:@"type" inDictionary:inNode withMap:@{
        @"peaking":   @( BiquadTypePeaking   ),
        @"lowpass":   @( BiquadTypeLowpass   ),
        @"highpass":  @( BiquadTypeHighpass  ),
        @"bandpass":  @( BiquadTypeBandpass  ),
        @"notch":     @( BiquadTypeNotch     ),
        @"lowshelf":  @( BiquadTypeLowshelf  ),
        @"highshelf": @( BiquadTypeHighshelf )
    }];
        
    if (_error) return nil;

    return [[Biquad alloc] initWithType:[typeNumber integerValue] frequency:frequency Q:Q gain:gain];
}


- (NoisyBiquadsNode *) _readBiquadsNode:(NSDictionary *)inNode
{
    inNode = [self _validateDictionary:inNode withTemplate:@{
        @"type":     @[ [NSString class], sRequired ],
        @"biquads":  @[ [NSArray  class], sRequired ],
    }];
    
    NSMutableArray *outBiquads = [NSMutableArray array];
    
    NSInteger index = 0;
    for (NSDictionary *inBiquad in [inNode objectForKey:@"biquads"]) {
        [self _pushPathComponent:@".biquads[%ld]", (long)index++];
        
        if ([inBiquad isKindOfClass:[NSDictionary class]]) {
            Biquad *outBiquad = [self _readBiquad:inBiquad];
            if (outBiquad) [outBiquads addObject:outBiquad];
        } else {
            [self _raiseError:@"Expected an object type"];
        }
        
        [self _popPathComponent];
    }

    if (_error) return NULL;
    
    double *coefficients = malloc(5 * [outBiquads count] * sizeof(double));

    [Biquad fillCoefficients:coefficients biquadArray:outBiquads sampleRate:_sampleRate];
    
    NoisyBiquadsNode *result = NoisyBiquadsNodeCreate(coefficients, [outBiquads count]);

    free(coefficients);
    
    return result;
}


- (NoisyDCBlockNode *) _readDCBlockNode:(NSDictionary *)inNode
{
    return NoisyDCBlockNodeCreate();
}


- (NoisyGainNode *) _readGainNode:(NSDictionary *)inNode
{
    inNode = [self _validateDictionary:inNode withTemplate:@{
        @"type": @[ [NSString class], sRequired ],
        @"gain": @[ [NSNumber class], sRequired ],
    }];
    
    if (_error) return NULL;
 
    double gain = [[inNode objectForKey:@"gain"] doubleValue];

    return NoisyGainNodeCreate(gain);
}


- (NoisyGeneratorNode *) _readGeneratorNode:(NSDictionary *)inNode
{
    inNode = [self _validateDictionary:inNode withTemplate:@{
        @"type":    @[ [NSString class], sRequired ],
        @"subtype": @[ [NSString class], @"uniform" ],
    }];
    
    NSNumber *subTypeNumber = [self _validateEnumKey:@"subtype" inDictionary:inNode withMap:@{
        @"uniform":  @( NoisyGeneratorTypeUniform  ),
        @"gaussian": @( NoisyGeneratorTypeGaussian ),
        @"brownian": @( NoisyGeneratorTypeBrownian ),
    }];

    if (_error) return NULL;
    
    NoisyGeneratorType generatorType = (NoisyGeneratorType)[subTypeNumber integerValue];
    uint64_t randomSeed = _forAutoGain ? _autoGainRandomSeed++ : arc4random();

    return NoisyGeneratorNodeCreate(generatorType, randomSeed);
}


- (NoisyNodeList *) _readNodeList:(NSArray *)inNodeArray
{
    NoisyNodeList *nodeList = NoisyNodeListCreate([inNodeArray count]);

    _nodeDepth++;

    NSInteger index = 0;

    for (NSDictionary *inNode in inNodeArray) {
        [self _pushPathComponent:@"[%ld]", (long)index++];

        if (![self _assertClass:[NSDictionary class] ofObject:inNode]) {
            break;
        }
        
        NSString *typeString = [inNode objectForKey:@"type"];
        NoisyNodeRef node = NULL;
        
        if (!typeString) {
            [self _raiseError:@"Missing required key: 'type'"];
            break;
        }

        if ([typeString isEqual:@"biquads"]) {
            node = [self _readBiquadsNode:inNode];
        } else if ([typeString isEqual:@"dcblock"]) {
            node = [self _readDCBlockNode:inNode];
        } else if ([typeString isEqual:@"gain"]) {
            node = [self _readGainNode:inNode];
        } else if ([typeString isEqual:@"generator"]) {
            node = [self _readGeneratorNode:inNode];
        } else if ([typeString isEqual:@"onepole"]) {
            node = [self _readOnePoleNode:inNode];
        } else if ([typeString isEqual:@"pinking"]) {
            node = [self _readPinkingNode:inNode];
        } else if ([typeString isEqual:@"split"]) {
            node = [self _readSplitNode:inNode];
        } else if ([typeString isEqual:@"stereo"]) {
            [self _readStereoNode:inNode];
        } else if ([typeString isEqual:@"zero"]) {
            [self _readZeroNode:inNode];
        } else {
            [self _pushPathComponent:@".type"];
            [self _raiseError:@"Unknown value: '%@'", typeString];
            [self _popPathComponent];
        }
        
        if (node) {
            NoisyNodeListAppend(nodeList, node);
        }

        [self _popPathComponent];

        if (_error) break;
    }
    
    _nodeDepth--;

    if (_error) {
        NoisyNodeListFree(nodeList);
        return NULL;
    }
    
    return nodeList;
}


- (NoisyOnePoleNode *) _readOnePoleNode:(NSDictionary *)inNode
{
    inNode = [self _validateDictionary:inNode withTemplate:@{
        @"type":      @[ [NSString class], sRequired   ],
        @"subtype":   @[ [NSString class], @"lowpass" ],
        @"frequency": @[ [NSNumber class], sRequired   ]
    }];

    NSNumber *subTypeNumber = [self _validateEnumKey:@"subtype" inDictionary:inNode withMap:@{
        @"highpass": @YES,
        @"lowpass":  @NO
    }];

    if (_error) return NULL;

    double frequency  = [[inNode objectForKey:@"frequency"] doubleValue];
    BOOL   isHighpass = [subTypeNumber boolValue];

    return NoisyOnePoleNodeCreate(frequency / _sampleRate, isHighpass);
}


- (NoisyPinkingNode *) _readPinkingNode:(NSDictionary *)inNode
{
    inNode = [self _validateDictionary:inNode withTemplate:@{
        @"type":    @[ [NSString class], sRequired ],
        @"subtype": @[ [NSString class], @"pk3"   ],
    }];

    NSNumber *subTypeNumber = [self _validateEnumKey:@"subtype" inDictionary:inNode withMap:@{
        @"pk3": @( NoisyPinkingTypePK3 ),
        @"pke": @( NoisyPinkingTypePKE ),
        @"rbj": @( NoisyPinkingTypeRBJ )
    }];;
 
    if (_error) return NULL;
    
    NoisyPinkingType pinkingType = (NoisyPinkingType)[subTypeNumber integerValue];
    
    return NoisyPinkingNodeCreate(pinkingType);
}


- (NoisySplitNode *) _readSplitNode:(NSDictionary *)inNode
{
    inNode = [self _validateDictionary:inNode withTemplate:@{
        @"type":     @[ [NSString class], sRequired ],
        @"programs": @[ [NSArray  class], sRequired ],
    }];

    if (_error) return NULL;

    NSArray *inPrograms = [inNode objectForKey:@"programs"];
    
    NoisySplitNode *splitNode = NoisySplitNodeCreate([inPrograms count]);

    [self _pushPathComponent:@".programs"];

    NSInteger index = 0;
    for (NSArray *inProgram in inPrograms) {
        [self _pushPathComponent:@"[%ld]", (long)index++];
        
        if ([self _assertClass:[NSArray class] ofObject:inProgram]) {
            NoisyNodeList *nodeList = [self _readNodeList:inProgram];
            if (nodeList) NoisySplitNodeAppendNodeList(splitNode, nodeList);
        }
        
        [self _popPathComponent];
        
        if (_error) break;
    }
    
    [self _popPathComponent];

    if (_error) {
        NoisyNodeFree(splitNode);
        return NULL;
    }

    return splitNode;
}


- (void) _readStereoNode:(NSDictionary *)inNode
{
    if (_leftNodeList || _rightNodeList) {
        [self _raiseError:@"A program may only have one stereo node"];
        // Error here.
        return;
    } else if (_nodeDepth > 1) {
        [self _raiseError:@"A stereo node cannot be a child of another node."];
    }

    inNode = [self _validateDictionary:inNode withTemplate:@{
        @"type":  @[ [NSString class], sRequired ],
        @"left":  @[ [NSArray  class], sRequired ],
        @"right": @[ [NSArray  class], sRequired ],
    }];

    [self _pushPathComponent:@".left"];
    NoisyNodeList *leftList  = [self _readNodeList:[inNode objectForKey:@"left"]];
    [self _popPathComponent];

    [self _pushPathComponent:@".right"];
    NoisyNodeList *rightList = [self _readNodeList:[inNode objectForKey:@"right"]];
    [self _popPathComponent];

    if (_error) {
        if (leftList)  NoisyNodeFree(leftList);
        if (rightList) NoisyNodeFree(rightList);
    } else {
        _leftNodeList  = leftList;
        _rightNodeList = rightList;
    }
}

- (NoisyZeroNode *) _readZeroNode:(NSDictionary *)inNode
{
    return NoisyZeroNodeCreate();
}


- (void) _parsePreset
{
    [self _pushPathComponent:@"$"];

    NSDictionary *rootDictionary = [_preset rootDictionary];

    rootDictionary = [self _validateDictionary:rootDictionary withTemplate:@{
        @"name":     @[ [NSString class] ],
        @"program":  @[ [NSArray  class], sRequired ],
        @"autogain": @[ [NSDictionary class] ]
    }];

    [self _pushPathComponent:@".autogain"];
    [self _readAutoGainSettings:[rootDictionary objectForKey:@"autogain"]];
    [self _popPathComponent];

    [self _pushPathComponent:@".program"];

    NSArray *programNodes = [rootDictionary objectForKey:@"program"];
    
    _headNodeList = [self _readNodeList:programNodes];
    
    if ((_channelCount > 1) && !_error && !_leftNodeList && !_rightNodeList) {
        _leftNodeList  = _headNodeList;
        _rightNodeList = [self _readNodeList:programNodes];
        _headNodeList  = NULL;
    }
    
    [self _popPathComponent];
    [self _popPathComponent];
}


#pragma mark - Public Methods



- (void) transferHeadNodeList: (NoisyNodeList **) outHeadNodeList
                 leftNodeList: (NoisyNodeList **) outLeftNodeList
                rightNodeList: (NoisyNodeList **) outRightNodeList
{
    if (outHeadNodeList) {
        *outHeadNodeList = _headNodeList;
        _headNodeList = NULL;
    }

    if (outLeftNodeList) {
        *outLeftNodeList = _leftNodeList;
        _leftNodeList = NULL;
    }

    if (outRightNodeList) {
        *outRightNodeList = _rightNodeList;
        _rightNodeList = NULL;
    }
}

@end

