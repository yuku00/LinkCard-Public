#define _POSIX_C_SOURCE 200809L
#include "WUNativeBoot.h"
#include <assert.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    char dir[]="/tmp/wu-boot-test.XXXXXX"; assert(mkdtemp(dir));
    int fd=open(dir,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); assert(fd>=0);
    WUNativeBootState s;
    assert(WUNativeBootBeginAt(fd,&s) && s.pending && s.failures==0);
    // Process exits / power loss before active-stable completion are conservative failures.
    assert(WUNativeBootBeginAt(fd,&s) && s.failures==1);
    assert(!WUNativeBootBeginAt(fd,&s) && s.blocked && s.failures==2);
    assert(!WUNativeBootStableAt(fd,&s));
    assert(!WUNativeBootBeginAt(fd,&s)); // isolation never self-clears just by foregrounding
    assert(WUNativeBootResetAt(fd,&s));
    assert(WUNativeBootBeginAt(fd,&s)); assert(WUNativeBootStableAt(fd,&s));
    assert(WUNativeBootBeginAt(fd,&s) && s.failures==0); assert(WUNativeBootStableAt(fd,&s));
    // Orphan temporary writes cannot replace the committed marker.
    int temp=openat(fd,".native-startup.orphan",O_WRONLY|O_CREAT,0600); assert(temp>=0); assert(write(temp,"broken",6)==6); close(temp);
    assert(WUNativeBootBeginAt(fd,&s) && s.failures==0); assert(WUNativeBootStableAt(fd,&s));
    int bad=openat(fd,"native-startup.guard",O_WRONLY|O_TRUNC); assert(bad>=0); assert(write(bad,"partial",7)==7); close(bad);
    assert(!WUNativeBootBeginAt(fd,&s) && s.blocked); assert(WUNativeBootResetAt(fd,&s));
    // Same-length bit flip, symlink, unavailable directory and failed durable commit fail closed.
    bad=openat(fd,"native-startup.guard",O_RDWR); assert(bad>=0); unsigned char byte=0; assert(pread(bad,&byte,1,8)==1); byte^=1; assert(pwrite(bad,&byte,1,8)==1); close(bad);
    assert(!WUNativeBootBeginAt(fd,&s)); assert(WUNativeBootResetAt(fd,&s));
    assert(unlinkat(fd,"native-startup.guard",0)==0);
    assert(symlinkat(".native-startup.orphan",fd,"native-startup.guard")==0);
    assert(!WUNativeBootBeginAt(fd,&s)); // never follows symlink; replaces it with blocked own state
    assert(!WUNativeBootBeginAt(-1,&s)); assert(!WUNativeBootResetAt(-1,&s));
    assert(!WUNativeBootBeginAt(fd,NULL));
    unlinkat(fd,"native-startup.guard",0); unlinkat(fd,".native-startup.orphan",0); close(fd); rmdir(dir);
    puts("PASS production startup guard: durable state, crash threshold, stable/reset, interrupted/corrupt writes, symlink and IO failure");
    return 0;
}
