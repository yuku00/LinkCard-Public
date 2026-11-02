#import "ExperimentalDelete.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static NSDictionary *refuse(NSString *reason) { return @{ @"called": @NO, @"reason": reason }; }
static BOOL signature(Class cls, SEL sel, BOOL meta, const char *ret, unsigned count, const char *arg) {
    Method m = meta ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!m || method_getNumberOfArguments(m) != count) return NO;
    char r[128] = {0}, a[128] = {0}, b[128] = {0};
    method_getReturnType(m, r, sizeof r); method_getArgumentType(m, 0, a, sizeof a);
    method_getArgumentType(m, 1, b, sizeof b);
    if (!((strcmp(r, ret) == 0) || (strcmp(ret, @encode(BOOL)) == 0 && (strcmp(r, "c") == 0 || strcmp(r, "B") == 0))) || strcmp(a, "@") || strcmp(b, ":")) return NO;
    if (count == 3) { method_getArgumentType(m, 2, a, sizeof a); if (strcmp(a, arg)) return NO; }
    return YES;
}
static BOOL validID(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length < 9 || s.length > 200 || ![s hasSuffix:@".webclip"] || [s hasPrefix:@"."]) return NO;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_ ."] invertedSet];
    return [s rangeOfCharacterFromSet:bad].location == NSNotFound && [s rangeOfString:@" "].location == NSNotFound;
}
// Walk every component without following symlinks, including the target directory.
static int openDirectory(NSString *path) {
    if (![path hasPrefix:@"/"] || ![path isEqualToString:path.stringByStandardizingPath]) return -1;
    int fd = open("/", O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if (fd < 0) return -1;
    for (NSString *part in path.pathComponents) {
        if ([part isEqualToString:@"/"]) continue;
        int next = openat(fd, part.fileSystemRepresentation, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        close(fd); if (next < 0) return -1; fd = next;
    }
    return fd;
}
static NSString *checkPlist(int dir) {
    int fd = openat(dir, "Info.plist", O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
    if (fd < 0) return @"无法安全读取 Info.plist";
    struct stat st; if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_nlink != 1 || st.st_size < 0 || st.st_size > 2*1024*1024) { close(fd); return @"Info.plist 类型或大小不安全"; }
    NSMutableData *data = [NSMutableData data]; char buf[16384]; ssize_t n;
    while ((n = read(fd, buf, sizeof buf)) > 0) { [data appendBytes:buf length:(NSUInteger)n]; if (data.length > 2*1024*1024) { close(fd); return @"Info.plist 超限"; } }
    close(fd); if (n < 0) return @"读取 Info.plist 失败";
    id p = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    if (![p isKindOfClass:NSDictionary.class]) return @"Info.plist 无效";
    if (![p[@"Title"] isKindOfClass:NSString.class] || ![p[@"Title"] isEqual:@"WCM-DELETE-TEST"]) return @"标题不是 WCM-DELETE-TEST";
    for (NSString *key in @[@"ConfigurationIsManaged", @"RemovalDisallowed"]) {
        id value = p[key];
        if (!value || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() || [value boolValue]) return [NSString stringWithFormat:@"%@ 缺失、非布尔值或为真", key];
    }
    return nil;
}
static NSDictionary *performDelete(NSString *identifier, NSString *root, Class cls) {
    if (!validID(identifier)) return refuse(@"标识符无效");
    NSString *expected = [root stringByAppendingPathComponent:identifier];
    int dir = openDirectory(expected); if (dir < 0) return refuse(@"源目录不可访问或路径包含符号链接");
    NSString *err = checkPlist(dir); if (err) { close(dir); return refuse(err); }
    SEL factory = NSSelectorFromString(@"webClipWithIdentifier:");
    SEL pathSel = NSSelectorFromString(@"pathForWebClipWithIdentifier:");
    SEL idSel = NSSelectorFromString(@"identifier"), managedSel = NSSelectorFromString(@"removalDisallowed"), removeSel = NSSelectorFromString(@"removeFromDisk");
    if (!cls || !signature(cls,factory,YES,"@",3,"@") || !signature(cls,pathSel,YES,"@",3,"@") || !signature(cls,idSel,NO,"@",2,NULL) || !signature(cls,managedSel,NO,@encode(BOOL),2,NULL) || !signature(cls,removeSel,NO,@encode(BOOL),2,NULL)) { close(dir); return refuse(@"UIWebClip 方法缺失或 ABI 签名不匹配"); }
    id (*classArg)(id, SEL, id) = (void *)objc_msgSend;
    id (*objectGet)(id, SEL) = (void *)objc_msgSend;
    BOOL (*boolGet)(id, SEL) = (void *)objc_msgSend;
    id path = classArg(cls,pathSel,identifier);
    if (![path isKindOfClass:NSString.class]) { close(dir); return refuse(@"运行时路径不是字符串"); }
    // /var is the system alias of /private/var; never resolve arbitrary symlinks.
    NSString *runtimePath = path;
    if ([runtimePath hasPrefix:@"/var/"]) runtimePath = [@"/private" stringByAppendingString:runtimePath];
    if (![runtimePath isEqualToString:expected] || ![[runtimePath stringByStandardizingPath] isEqualToString:expected]) { close(dir); return refuse(@"运行时路径与选中目录不一致或未规范化"); }
    id object = classArg(cls,factory,identifier);
    if (!object || ![object isKindOfClass:cls]) { close(dir); return refuse(@"无法取得匹配的 UIWebClip 实例"); }
    // A subclass may override methods: check the actual dispatch class as well.
    Class actual = object_getClass(object);
    if (!signature(actual,idSel,NO,"@",2,NULL) || !signature(actual,managedSel,NO,@encode(BOOL),2,NULL) || !signature(actual,removeSel,NO,@encode(BOOL),2,NULL)) { close(dir); return refuse(@"实例方法 ABI 不匹配"); }
    id actualID = objectGet(object,idSel);
    if (![actualID isKindOfClass:NSString.class] || ![actualID isEqualToString:identifier]) { close(dir); return refuse(@"实例 identifier 不匹配"); }
    if (boolGet(object,managedSel)) { close(dir); return refuse(@"运行时禁止移除"); }
    // Reopen to reject swapped directory; re-read policy immediately before the one call.
    int again = openDirectory(expected); struct stat a,b;
    if (again < 0 || fstat(dir,&a) || fstat(again,&b) || a.st_dev != b.st_dev || a.st_ino != b.st_ino) { if (again >= 0) close(again); close(dir); return refuse(@"源目录在检查期间发生变化"); }
    err = checkPlist(again); close(again); close(dir); if (err) return refuse(err);
    BOOL result = boolGet(object,removeSel); // exactly one invocation
    struct stat post; int parent = openDirectory(root);
    NSString *state = @"未知（无法检查）";
    if (parent >= 0) { if (fstatat(parent, identifier.fileSystemRepresentation, &post, AT_SYMLINK_NOFOLLOW) == 0) state = @"仍存在"; else if (errno == ENOENT) state = @"不存在"; close(parent); }
    return @{ @"called": @YES, @"returned": @(result), @"source": state, @"reason": @"系统返回值和目录状态不证明桌面图标已清理" };
}
NSDictionary *WCMExperimentalDelete(NSString *identifier) { return performDelete(identifier, @"/private/var/mobile/Library/WebClips", NSClassFromString(@"UIWebClip")); }
NSDictionary *WCMExperimentalDeleteForTesting(NSString *identifier, NSString *root, Class mockClass) { return performDelete(identifier, root, mockClass); }
