// (c) 2019-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#ifdef __cplusplus
extern "C" {
#endif

extern NSString *GetStringForFourCharCode(OSStatus fcc);

extern BOOL CheckError(OSStatus error, NSString *operation);


#ifdef __cplusplus
}
#endif

