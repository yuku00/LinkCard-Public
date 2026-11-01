#define _POSIX_C_SOURCE 200809L
#include "WUNativeBoot.h"
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#define NAME "native-startup.guard"
typedef struct { uint32_t magic, version, failures, pending, blocked, check; } Disk;
static uint32_t Check(Disk d) { return d.magic ^ d.version ^ d.failures ^ (d.pending<<8) ^ (d.blocked<<16) ^ 0x19ba73d4; }
static bool Write(int dir, WUNativeBootState s) {
    Disk d={0x57554247,1,s.failures,s.pending,s.blocked,0}; d.check=Check(d);
    char tmp[96]; int fd=-1;
    for(unsigned i=0;i<128 && fd<0;i++) {
        snprintf(tmp,sizeof(tmp),".native-startup.%ld.%u",(long)getpid(),i);
        fd=openat(dir,tmp,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
        if(fd<0 && errno!=EEXIST) return false;
    }
    if(fd<0) return false;
    size_t n=0; while(n<sizeof(d)) { ssize_t v=write(fd,(char *)&d+n,sizeof(d)-n); if(v<0 && errno==EINTR) continue; if(v<=0) break; n+=(size_t)v; }
    bool ok=n==sizeof(d) && fsync(fd)==0;
    if(close(fd)) ok=false;
    if(ok) ok=renameat(dir,tmp,dir,NAME)==0;
    if(!ok) unlinkat(dir,tmp,0);
    // Unlike general preferences, the guard must be durable before suppressing recovery.
    return ok && fsync(dir)==0;
}
static bool Read(int dir,WUNativeBootState *s) {
    int fd=openat(dir,NAME,O_RDONLY|O_NOFOLLOW);
    if(fd<0) return errno==ENOENT;
    struct stat st; Disk d; memset(&d,0,sizeof(d));
    bool ok=fstat(fd,&st)==0 && S_ISREG(st.st_mode) && st.st_size==(off_t)sizeof(d);
    size_t n=0;
    while(ok && n<sizeof(d)) { ssize_t v=read(fd,(char *)&d+n,sizeof(d)-n); if(v<0 && errno==EINTR) continue; if(v<=0) break; n+=(size_t)v; }
    close(fd);
    if(!ok || n!=sizeof(d) || d.magic!=0x57554247 || d.version!=1 || d.check!=Check(d) || d.pending>1 || d.blocked>1 || d.failures>2) return false;
    *s=(WUNativeBootState){d.failures,d.pending,d.blocked}; return true;
}
bool WUNativeBootBeginAt(int dir,WUNativeBootState *state) {
    if(!state) return false;
    WUNativeBootState s={0};
    if(dir<0 || !Read(dir,&s)) s=(WUNativeBootState){2,0,1};
    if(s.pending && s.failures<2) s.failures++;
    if(s.failures>=2) s.blocked=1;
    s.pending=!s.blocked;
    bool ok=Write(dir,s); if(!ok) s.blocked=1;
    *state=s; return ok && !s.blocked;
}
bool WUNativeBootStableAt(int dir,WUNativeBootState *state) {
    if(!state || state->blocked || !state->pending) return false;
    WUNativeBootState next={0};
    if(!Write(dir,next)) return false;
    *state=next; return true;
}
bool WUNativeBootResetAt(int dir,WUNativeBootState *state) {
    if(!state) return false;
    WUNativeBootState next={0}; if(!Write(dir,next)) return false;
    *state=next; return true;
}
