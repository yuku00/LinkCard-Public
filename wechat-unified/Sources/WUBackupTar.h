#ifndef WU_BACKUP_TAR_H
#define WU_BACKUP_TAR_H
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

/* USTAR, uncompressed, streamed. Any unsupported path/type or I/O failure aborts. */
static int wu_tar_write(int fd, const void *p, size_t n) {
    const char *b=p; while(n) { ssize_t w=write(fd,b,n); if(w<0 && errno==EINTR) continue; if(w<=0) return 0; b+=w; n-=(size_t)w; } return 1;
}
static int wu_tar_same(const struct stat *a, const struct stat *b) {
#if defined(__APPLE__)
#define WU_MT st_mtimespec
#define WU_CT st_ctimespec
#else
#define WU_MT st_mtim
#define WU_CT st_ctim
#endif
    return a->st_dev==b->st_dev && a->st_ino==b->st_ino && a->st_mode==b->st_mode && a->st_size==b->st_size && a->WU_MT.tv_sec==b->WU_MT.tv_sec && a->WU_MT.tv_nsec==b->WU_MT.tv_nsec && a->WU_CT.tv_sec==b->WU_CT.tv_sec && a->WU_CT.tv_nsec==b->WU_CT.tv_nsec;
#undef WU_MT
#undef WU_CT
}
static int wu_tar_octal(char *p, size_t n, uint64_t x) {
    if(n<2) return 0; memset(p,'0',n-1); p[n-1]=0;
    for(size_t i=n-1;i>0 && x;i--) { p[i-1]=(char)('0'+(x&7)); x>>=3; } return x==0;
}
static int wu_tar_header(int out, const char *path, uint64_t size, int dir) {
    char h[512]={0}; size_t len=strlen(path); if(!len || len>255 || size>077777777777ULL) return 0;
    if(len<=100) memcpy(h,path,len);
    else { const char *split=NULL; for(const char *p=path;*p;p++) if(*p=='/' && (size_t)(p-path)<=155 && strlen(p+1)<=100 && p[1]) split=p; if(!split) return 0; memcpy(h+345,path,(size_t)(split-path)); memcpy(h,split+1,strlen(split+1)); }
    if(!wu_tar_octal(h+100,8,dir?0700:0600) || !wu_tar_octal(h+108,8,0) || !wu_tar_octal(h+116,8,0) || !wu_tar_octal(h+124,12,size) || !wu_tar_octal(h+136,12,0)) return 0;
    memset(h+148,' ',8); h[156]=dir?'5':'0'; memcpy(h+257,"ustar",5); h[263]='0'; h[264]='0'; unsigned sum=0; for(size_t i=0;i<512;i++) sum+=(unsigned char)h[i];
    if(!wu_tar_octal(h+148,8,sum)) return 0; return wu_tar_write(out,h,512);
}
static int wu_tar_node(int parent, const char *name, const char *path, int out, unsigned depth) {
    if(depth>32) return 0;
    struct stat before,after,entry;
    if(fstatat(parent,name,&entry,AT_SYMLINK_NOFOLLOW) || (!S_ISREG(entry.st_mode) && !S_ISDIR(entry.st_mode))) return 0;
    int flags=O_RDONLY|O_NOFOLLOW; if(S_ISDIR(entry.st_mode)) flags|=O_DIRECTORY;
    int fd=openat(parent,name,flags); if(fd<0) return 0;
    int ok=fstat(fd,&before)==0 && wu_tar_same(&entry,&before);
    if(ok && S_ISDIR(before.st_mode)) {
        ok=wu_tar_header(out,path,0,1); int copy=dup(fd); DIR *d=copy>=0?fdopendir(copy):NULL; if(!d) { if(copy>=0) close(copy); ok=0; }
        if(d) { struct dirent *e; errno=0; while(ok && (e=readdir(d))) { if(!strcmp(e->d_name,".") || !strcmp(e->d_name,"..")) continue; size_t n=strlen(path)+strlen(e->d_name)+2; char *sub=malloc(n); if(!sub) { ok=0; break; } snprintf(sub,n,"%s/%s",path,e->d_name); ok=wu_tar_node(fd,e->d_name,sub,out,depth+1); free(sub); errno=0; } if(errno) ok=0; closedir(d); }
    } else if(ok && S_ISREG(before.st_mode) && before.st_size>=0) {
        uint64_t left=(uint64_t)before.st_size; ok=wu_tar_header(out,path,left,0); char buf[65536], check[65536]; off_t start=lseek(out,0,SEEK_CUR), offset=0; if(start<0) ok=0;
        while(ok && left) { size_t want=left<sizeof(buf)?(size_t)left:sizeof(buf); ssize_t n=read(fd,buf,want); if(n<0 && errno==EINTR) continue; if(n<=0 || !wu_tar_write(out,buf,(size_t)n)) { ok=0; break; } left-=(uint64_t)n; }
        while(ok && offset<before.st_size) { size_t want=(uint64_t)(before.st_size-offset)<sizeof(buf)?(size_t)(before.st_size-offset):sizeof(buf); ssize_t a=pread(fd,buf,want,offset), b=pread(out,check,want,start+offset); if(a!=(ssize_t)want || b!=a || memcmp(buf,check,want)) { ok=0; break; } offset+=(off_t)want; }
        if(ok && (before.st_size%512)) { char z[512]={0}; ok=wu_tar_write(out,z,512-(size_t)(before.st_size%512)); }
    } else ok=0;
    if(fstat(fd,&after) || !wu_tar_same(&before,&after) || fstatat(parent,name,&entry,AT_SYMLINK_NOFOLLOW) || !wu_tar_same(&before,&entry)) ok=0;
    close(fd); return ok;
}
/* Caller creates an exclusive private output file, deletes it on failure. */
static int wu_backup_tar(int support, int out, const void *preferences, size_t preferencesLength) {
    struct stat st, supportBefore, supportAfter; if(fstat(support,&supportBefore)) return 0;
    if(fstatat(support,"WeChatUnified",&st,AT_SYMLINK_NOFOLLOW) || !S_ISDIR(st.st_mode)) return 0;
    if(!wu_tar_node(support,"WeChatUnified","WeChatUnified",out,0)) return 0;
    if(fstatat(support,"WeChatUnifiedEmoticons",&st,AT_SYMLINK_NOFOLLOW)==0) { if(!S_ISDIR(st.st_mode) || !wu_tar_node(support,"WeChatUnifiedEmoticons","WeChatUnifiedEmoticons",out,0)) return 0; }
    else if(errno!=ENOENT) return 0;
    if(preferences) {
        if(!wu_tar_header(out,"WUStatsSectionPreferences.plist",preferencesLength,0)) return 0;
        off_t start=lseek(out,0,SEEK_CUR); if(start<0 || !wu_tar_write(out,preferences,preferencesLength)) return 0;
        char check[4096]; size_t offset=0; while(offset<preferencesLength) { size_t n=preferencesLength-offset<sizeof(check)?preferencesLength-offset:sizeof(check); if(pread(out,check,n,start+(off_t)offset)!=(ssize_t)n || memcmp((const char *)preferences+offset,check,n)) return 0; offset+=n; }
        if(preferencesLength%512) { char pad[512]={0}; if(!wu_tar_write(out,pad,512-preferencesLength%512)) return 0; }
    }
    if(fstat(support,&supportAfter) || !wu_tar_same(&supportBefore,&supportAfter)) return 0;
    char z[1024]={0}; return wu_tar_write(out,z,sizeof(z)) && fsync(out)==0;
}
#endif
