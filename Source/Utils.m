// (c) 2019-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "Utils.h"


NSString *GetStringForFourCharCode(OSStatus fcc)
{
    char str[20] = {0};

    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(*(UInt32 *)&fcc);

    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else {
        return [NSString stringWithFormat:@"%ld", (long)fcc];
    }
    
    return [NSString stringWithCString:str encoding:NSUTF8StringEncoding];
}


BOOL CheckError(OSStatus error, NSString *operation)
{
    if (error == noErr) {
        return YES;
    }

    NSLog(@"Error: %@ (%@)", operation, GetStringForFourCharCode(error));

    return NO;
}

