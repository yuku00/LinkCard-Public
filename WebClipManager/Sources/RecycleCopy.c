#include "RecycleCopy.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>

static int valid(const char *s, int clip) {
    size_t n = s ? strlen(s) : 0;
    if (!n || n > 200 || s[0] == '.') return 0;
    for (size_t i=0; i<n; ++i) {
        char c=s[i];
        if (!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='-'||c=='_')) {
            if (c!='.') return 0;
        }
    }
    return !clip || (n>8 && !strcmp(s+n-8,".webclip"));
}
static int writeall(int fd, const void *buf, size_t n) {
    const char *p=buf;
    while(n) { ssize_t w=write(fd,p,n); if(w<0&&errno==EINTR) continue; if(w<=0) return -1; p+=w; n-=(size_t)w; }
    return 0;
}
static int copytree(int src, int dst, int depth, WCMCancel cancel, void *ctx) {
    if (depth>64) { errno=ELOOP; return -1; }
    int duplicate=dup(src); if (duplicate<0) return -1;
    DIR *dir=fdopendir(duplicate); if(!dir) { close(duplicate); return -1; }
    struct dirent *entry; int result=0; errno=0;
    while ((entry=readdir(dir))) {
        if (!strcmp(entry->d_name,".") || !strcmp(entry->d_name,"..")) { errno=0; continue; }
        if (cancel && cancel(ctx)) { errno=ECANCELED; result=-1; break; }
        struct stat before, opened, after;
        if (fstatat(src,entry->d_name,&before,AT_SYMLINK_NOFOLLOW)<0) { result=-1; break; }
        if (S_ISDIR(before.st_mode)) {
            int in=openat(src,entry->d_name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
            if(in<0) { result=-1; break; }
            if(fstat(in,&opened)<0 || opened.st_dev!=before.st_dev || opened.st_ino!=before.st_ino || mkdirat(dst,entry->d_name,0700)<0) { close(in); result=-1; break; }
            int out=openat(dst,entry->d_name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
            if(out<0) { close(in); result=-1; break; }
            result=copytree(in,out,depth+1,cancel,ctx); if(!result && fsync(out)<0) result=-1;
            close(out); close(in); if(result) break;
        } else if (S_ISREG(before.st_mode) && before.st_nlink==1) {
            int in=openat(src,entry->d_name,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
            if(in<0) { result=-1; break; }
            if(fstat(in,&opened)<0 || !S_ISREG(opened.st_mode) || opened.st_nlink!=1 || opened.st_dev!=before.st_dev || opened.st_ino!=before.st_ino) { close(in); errno=EINVAL; result=-1; break; }
            int out=openat(dst,entry->d_name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
            if(out<0) { close(in); result=-1; break; }
            char buffer[65536]; off_t total=0;
            for (;;) {
                if(cancel && cancel(ctx)) { errno=ECANCELED; result=-1; break; }
                ssize_t n=read(in,buffer,sizeof buffer); if(n<0&&errno==EINTR) continue;
                if(n<0) { result=-1; break; } if(!n) break;
                if(writeall(out,buffer,(size_t)n)<0) { result=-1; break; } total+=n;
            }
            if(!result && (fstat(in,&after)<0 || after.st_size!=opened.st_size || total!=opened.st_size || after.st_mtime!=opened.st_mtime || after.st_ctime!=opened.st_ctime || fsync(out)<0)) { errno=EIO; result=-1; }
            if(close(out)<0 && !result) result=-1; close(in); if(result) break;
        } else { errno=EINVAL; result=-1; break; }
        errno=0;
    }
    if(!result && errno) result=-1;
    int saved=errno; closedir(dir); errno=saved; return result;
}
int WCMRecycleCopy(int sourceRootFD,int recycleRootFD,const char *identifier,const char *transaction,WCMCancel cancelled,void *context) {
    if(!valid(identifier,1) || !valid(transaction,0)) { errno=EINVAL; return -1; }
    if(cancelled && cancelled(context)) { errno=ECANCELED; return -1; }
    int src=openat(sourceRootFD,identifier,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(src<0) return -1;
    char tmp[224]; if(snprintf(tmp,sizeof tmp,".incomplete-%s",transaction)>=(int)sizeof tmp) { close(src); errno=EINVAL; return -1; }
    if(mkdirat(recycleRootFD,tmp,0700)<0) { close(src); return -1; }
    int dir=openat(recycleRootFD,tmp,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(dir<0) { close(src); return -1; }
    int result=-1;
    if(mkdirat(dir,"files",0700)<0) goto done;
    int files=openat(dir,"files",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(files<0) goto done;
    int copied=copytree(src,files,0,cancelled,context);
    if(!copied && fsync(files)<0) copied=-1;
    close(files); if(copied) goto done;
    if(cancelled && cancelled(context)) { errno=ECANCELED; goto done; }
    int manifest=openat(dir,"manifest.tmp",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(manifest<0) goto done;
    char body[512]; int n=snprintf(body,sizeof body,"version=1\nidentifier=%s\nstatus=backupOnly\n",identifier);
    int m= n>0 && n<(int)sizeof body && writeall(manifest,body,(size_t)n)==0 && fsync(manifest)==0;
    if(close(manifest)<0) m=0;
    if(!m || renameat(dir,"manifest.tmp",dir,"manifest")<0 || fsync(dir)<0) goto done;
    /* No overwrite: link-free reservation of destination followed by rename of the
       transaction directory is not portable; publish by atomically renaming manifest
       inside its unique, O_EXCL-created directory instead. */
    result=0;
done:
    { int saved=errno; close(dir); close(src); errno=saved; }
    return result;
}
