#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>
#include <mach-o/dyld.h>
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
static const NSUInteger cap = 8 * 1024 * 1024;
static int fixedRoot(void) {
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    const char *parts[] = {"private", "var", "mobile", "Library", "WebClips"};
    for (unsigned i = 0; i < 5 && fd >= 0; i++) {
        int next = openat(fd, parts[i], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        int saved = errno; close(fd); fd = next; errno = saved;
    }
    return fd;
}
static NSData *readFile(int fd, const char *name, size_t limit, int *error) {
    int file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (file < 0) { *error = errno; return nil; }
    struct stat st;
    if (fstat(file, &st) || !S_ISREG(st.st_mode) || st.st_size < 0 || st.st_size > limit) {
        *error = EINVAL; close(file); return nil;
    }
    NSMutableData *data = [NSMutableData data];
    unsigned char buffer[16384]; ssize_t count;
    while ((count = read(file, buffer, sizeof(buffer))) != 0) {
        if (count < 0) { if (errno == EINTR) continue; *error = errno; close(file); return nil; }
        if (data.length + count > limit) { *error = EFBIG; close(file); return nil; }
        [data appendBytes:buffer length:count];
    }
    close(file); return data;
}
static int reply(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (!data || data.length > cap) return 74;
    const char *p = data.bytes; size_t left = data.length;
    while (left) { ssize_t n = write(STDOUT_FILENO, p, left); if (n < 0 && errno == EINTR) continue; if (n <= 0) return 74; p += n; left -= n; }
    return 0;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2 || strlen(argv[1]) != 12 || strcmp(argv[1], "webclip-list")) return 64;
        char self[4096], parent[4096]; uint32_t size = sizeof(self);
        if (_NSGetExecutablePath(self, &size) || proc_pidpath(getppid(), parent, sizeof(parent)) <= 0) return 77;
        NSString *expected = [[@(self) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"WebClipManager"];
        if (![[expected stringByResolvingSymlinksInPath] isEqualToString:[@(parent) stringByResolvingSymlinksInPath]]) return 77;
        // Deliberately retain caller's UID: root/persona is not required by current evidence.
        int root = fixedRoot();
        if (root < 0) return reply(@{@"version":@1, @"errno":@(errno), @"clips":@[], @"skipped":@0});
        DIR *directory = fdopendir(root);
        if (!directory) { int e = errno; close(root); return reply(@{@"version":@1, @"errno":@(e), @"clips":@[], @"skipped":@0}); }
        NSMutableArray *clips = [NSMutableArray array]; NSUInteger skipped = 0, visited = 0, used = 0; int failure = 0;
        struct dirent *entry;
        for (;;) {
            errno = 0; entry = readdir(directory);
            if (!entry) { if (errno) failure = errno; break; }
            if (++visited > 4096) { failure = EFBIG; break; }
            NSString *name = [[NSString alloc] initWithUTF8String:entry->d_name];
            if (!name || ![name hasSuffix:@".webclip"] || [name containsString:@"/"] || [name containsString:@"\\"] || name.length > 255) continue;
            int child = openat(root, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (child < 0) { skipped++; continue; }
            int e = 0; NSData *data = readFile(child, "Info.plist", 2 * 1024 * 1024, &e);
            id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil] : nil;
            if (![plist isKindOfClass:NSDictionary.class]) { close(child); skipped++; continue; }
            NSString *title = [plist[@"Title"] isKindOfClass:NSString.class] ? plist[@"Title"] : name;
            NSString *url = [plist[@"URL"] isKindOfClass:NSString.class] ? plist[@"URL"] : @"";
            if (title.length > 8192 || url.length > 65536) { close(child); skipped++; continue; }
            NSMutableDictionary *clip = [@{@"id":name, @"title":title, @"url":url,
                @"fullScreen":@([plist[@"FullScreen"] respondsToSelector:@selector(boolValue)] && [plist[@"FullScreen"] boolValue]),
                @"removalDisallowed":@([plist[@"RemovalDisallowed"] respondsToSelector:@selector(boolValue)] && [plist[@"RemovalDisallowed"] boolValue])} mutableCopy];
            for (NSString *icon in @[@"icon.png", @"icon@2x.png", @"icon@3x.png"]) {
                NSData *image = readFile(child, icon.UTF8String, 256 * 1024, &e);
                if (image) { clip[@"icon"] = [image base64EncodedStringWithOptions:0]; break; }
            }
            close(child);
            NSData *encoded = [NSJSONSerialization dataWithJSONObject:clip options:0 error:nil];
            if (!encoded || used + encoded.length > cap - 65536 || clips.count >= 1000) { failure = EFBIG; break; }
            used += encoded.length + 1; [clips addObject:clip];
        }
        closedir(directory);
        // Fail closed rather than presenting a truncated listing as a complete scan.
        return reply(@{@"version":@1, @"errno":@(failure), @"clips":failure ? @[] : clips, @"skipped":@(skipped)});
    }
}
