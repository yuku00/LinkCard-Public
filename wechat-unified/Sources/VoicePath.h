#import <Foundation/Foundation.h>
// Resolve only the system-provided home alias; never follow links below that root.
static inline NSString *WUVoiceCanonicalLocalPath(NSString *path) {
    if(![path isKindOfClass:NSString.class] || !path.isAbsolutePath) return nil;
    NSString *home=NSHomeDirectory().stringByStandardizingPath;
    NSString *canonical=home.stringByResolvingSymlinksInPath;
    NSString *plain=path.stringByStandardizingPath;
    NSString *prefix=[home stringByAppendingString:@"/"];
    if(![home isEqual:canonical] && [plain hasPrefix:prefix])
        plain=[canonical stringByAppendingPathComponent:[plain substringFromIndex:prefix.length]];
    if(![plain hasPrefix:[canonical stringByAppendingString:@"/"]] || ![plain isEqual:plain.stringByResolvingSymlinksInPath]) return nil;
    return plain;
}
