#import <Foundation/Foundation.h>
// Returns only measured PCM duration and peaks; never guesses a raw codec layout.
NSDictionary *WUVoiceDecode(NSData *encoded);
NSData *WUVoiceReadLocal(NSString *path);
