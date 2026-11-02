#ifndef WU_EMOTICON_LIBRARY_SAFETY_H
#define WU_EMOTICON_LIBRARY_SAFETY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
// The descriptor walk prevents an ancestor symlink from redirecting a commit.
static inline int WUEmojiOpenDirectory(const char *path) {
    if(!path || path[0]!='/') return -1;
    char *copy=strdup(path); if(!copy) return -1;
    int fd=open("/",O_RDONLY|O_DIRECTORY|O_NOFOLLOW); char *save=NULL;
#if defined(__APPLE__)
    // Darwin's system /var alias points to /private/var; retain no-follow checks below it.
    if(!strncmp(path,"/var/",5)) {
        char target[32]; ssize_t n=readlink("/var",target,sizeof(target)-1);
        if(n>0) { target[n]='\0'; if(!strcmp(target,"private/var") || !strcmp(target,"/private/var")) { close(fd); fd=open("/private",O_RDONLY|O_DIRECTORY|O_NOFOLLOW); } }
    }
#endif
    for(char *p=strtok_r(copy,"/",&save);p && fd>=0;p=strtok_r(NULL,"/",&save)) {
        if(!strcmp(p,".") || !strcmp(p,"..")) { close(fd); fd=-1; break; }
        int next=openat(fd,p,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); close(fd); fd=next;
    }
    free(copy); return fd;
}
static inline bool WUEmojiOwnedIndex(int dir) {
    struct stat st;
    if(fstatat(dir,"index.plist",&st,AT_SYMLINK_NOFOLLOW)) return errno==ENOENT;
    return S_ISREG(st.st_mode) && st.st_nlink==1 && st.st_size>=0 && st.st_size<=64*1024*1024;
}
static inline bool WUEmojiAtomicCommit(const char *directory, const char *temporary, const void *bytes, size_t length, bool (*current)(void *), void *context) {
    if(!bytes || !length || length>64*1024*1024 || !current || !current(context) || !temporary || strlen(temporary)!=36 || strchr(temporary,'/') || !strcmp(temporary,"index.plist")) return false;
    int dir=WUEmojiOpenDirectory(directory); if(dir<0) return false;
    if(!WUEmojiOwnedIndex(dir)) { close(dir); return false; }
    int fd=openat(dir,temporary,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(fd<0) { close(dir); return false; }
    size_t pos=0; bool ok=true;
    while(pos<length) {
        ssize_t n=write(fd,(const char *)bytes+pos,length-pos);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) { ok=false; break; } pos+=(size_t)n;
    }
    if(ok) ok=fsync(fd)==0 && lseek(fd,0,SEEK_SET)==0;
    pos=0; char buffer[4096];
    while(ok && pos<length) {
        size_t want=length-pos; if(want>sizeof buffer) want=sizeof buffer;
        ssize_t n=read(fd,buffer,want); if(n<0 && errno==EINTR) continue;
        if(n<=0 || memcmp(buffer,(const char *)bytes+pos,(size_t)n)) { ok=false; break; } pos+=(size_t)n;
    }
    struct stat st; ok=ok && fstat(fd,&st)==0 && S_ISREG(st.st_mode) && st.st_nlink==1 && (uint64_t)st.st_size==length;
    if(close(fd)!=0) ok=false;
    if(ok) ok=WUEmojiOwnedIndex(dir) && current(context);
    if(ok) ok=renameat(dir,temporary,dir,"index.plist")==0;
    if(!ok) unlinkat(dir,temporary,0);
    // A failed directory fsync after rename cannot undo a committed index.
    if(ok) (void)fsync(dir);
    close(dir); return ok;
}
#endif
