#import <Foundation/Foundation.h>
// Returns only measured PCM duration and peaks; never guesses a raw codec layout.
NSDictionary *WUVoiceDecode(NSData *encoded);
NSDictionary *WUVoiceDecodeCancellable(NSData *encoded, NSProgress *cancellation);
NSData *WUVoiceReadLocal(NSString *path);
// Converts recognized AudioToolbox containers locally; never establishes host sendability.
NSData *WUVoiceTranscodeSilk(NSData *data, BOOL (^current)(void));
