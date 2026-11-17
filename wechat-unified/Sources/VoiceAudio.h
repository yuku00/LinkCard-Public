#import <Foundation/Foundation.h>
// Returns only measured PCM duration and peaks; never guesses a raw codec layout.
NSDictionary *WUVoiceDecode(NSData *encoded);
NSDictionary *WUVoiceDecodeCancellable(NSData *encoded, NSProgress *cancellation);
NSData *WUVoiceReadLocal(NSString *path);
// Converts supported local audio to validated Tencent SILK; portable metadata is not trusted.
NSData *WUVoiceTranscodeSilk(NSData *data, BOOL (^current)(void));
