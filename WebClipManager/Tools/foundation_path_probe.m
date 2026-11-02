#import <Foundation/Foundation.h>
int main(void) { @autoreleasepool {
    NSArray *paths = @[@"/private/var/mobile/Library/WebClips/SYNTHETIC.webclip", @"/var/mobile/Library/WebClips/SYNTHETIC.webclip", @"/private/var/../var/mobile/Library/WebClips/SYNTHETIC.webclip", @"/var//mobile/Library/WebClips/SYNTHETIC.webclip"];
    for (NSString *p in paths) printf("input=%s standardized=%s unchanged=%s\n", p.UTF8String, p.stringByStandardizingPath.UTF8String, [p isEqualToString:p.stringByStandardizingPath] ? "yes" : "no");
} return 0; }
