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
static int unchanged(const struct stat *a, const struct stat *b) {
#ifdef __APPLE__
    return a->st_size==b->st_size && a->st_mtimespec.tv_sec==b->st_mtimespec.tv_sec && a->st_mtimespec.tv_nsec==b->st_mtimespec.tv_nsec && a->st_ctimespec.tv_sec==b->st_ctimespec.tv_sec && a->st_ctimespec.tv_nsec==b->st_ctimespec.tv_nsec;
#else
    return a->st_size==b->st_size && a->st_mtim.tv_sec==b->st_mtim.tv_sec && a->st_mtim.tv_nsec==b->st_mtim.tv_nsec && a->st_ctim.tv_sec==b->st_ctim.tv_sec && a->st_ctim.tv_nsec==b->st_ctim.tv_nsec;
#endif
}
static int copytree(int src, int dst, int depth, WCMCancel cancel, void *ctx) {
    if (depth>64) { errno=ELOOP; return -1; }
    struct stat dirBefore, dirAfter;
    if (fstat(src, &dirBefore)<0) return -1;
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
            if(!result && (fstat(in,&after)<0 || !unchanged(&opened,&after) || total!=opened.st_size || fsync(out)<0)) { errno=EIO; result=-1; }
            if(close(out)<0 && !result) result=-1; close(in); if(result) break;
        } else { errno=EINVAL; result=-1; break; }
        errno=0;
    }
    if(!result && errno) result=-1;
    if(!result && (fstat(src,&dirAfter)<0 || !unchanged(&dirBefore,&dirAfter))) { errno=EIO; result=-1; }
    int saved=errno; closedir(dir); errno=saved; return result;
}
int WCMRecycleCopy(int sourceRootFD,int recycleRootFD,const char *identifier,const char *transaction,WCMCancel cancelled,void *context) {
    if(!valid(identifier,1) || !valid(transaction,0)) { errno=EINVAL; return -1; }
    if(cancelled && cancelled(context)) { errno=ECANCELED; return -1; }
    int src=openat(sourceRootFD,identifier,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(src<0) return -1;
    struct stat info, sourceStart, sourceNow, sourcePath;
    if(fstat(src,&sourceStart)<0) { close(src); return -1; }
    if(fstatat(src,"Info.plist",&info,AT_SYMLINK_NOFOLLOW)<0 || !S_ISREG(info.st_mode) || info.st_nlink!=1) { close(src); errno=EINVAL; return -1; }
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
    if(fstat(src,&sourceNow)<0 || fstatat(sourceRootFD,identifier,&sourcePath,AT_SYMLINK_NOFOLLOW)<0 ||
       !S_ISDIR(sourcePath.st_mode) || sourceStart.st_dev!=sourcePath.st_dev ||
       sourceStart.st_ino!=sourcePath.st_ino || !unchanged(&sourceStart,&sourceNow)) {
        errno=ESTALE; goto done;
    }
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

static int transaction_name(const char *name) {
    static const char prefix[] = ".incomplete-";
    return name && !strncmp(name,prefix,sizeof(prefix)-1) && valid(name+sizeof(prefix)-1,0);
}
/* Returns an opened transaction only after strict, bounded manifest validation. */
static int inspect_open(int root, const char *name, char *id, size_t cap) {
    if (!transaction_name(name)) { errno=EINVAL; return -1; }
    int dir=openat(root,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(dir<0) return -1;
    int fd=openat(dir,"manifest",O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
    if(fd<0) { close(dir); return -1; }
    struct stat st; char body[512]; size_t used=0; int ok=0;
    if(fstat(fd,&st)<0 || !S_ISREG(st.st_mode) || st.st_nlink!=1 || st.st_size<=0 || st.st_size>=(off_t)sizeof(body)) goto end;
    while(used<(size_t)st.st_size) {
        ssize_t n=read(fd,body+used,(size_t)st.st_size-used);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) goto end;
        used+=(size_t)n;
    }
    body[used]='\0';
    const char prefix[]="version=1\nidentifier=";
    const char suffix[]="\nstatus=backupOnly\n";
    if(used<sizeof(prefix)-1+sizeof(suffix)-1 || memcmp(body,prefix,sizeof(prefix)-1)) goto end;
    size_t len=used-(sizeof(prefix)-1)-(sizeof(suffix)-1);
    if(!len || len>=cap || memcmp(body+used-(sizeof(suffix)-1),suffix,sizeof(suffix)-1)) goto end;
    memcpy(id,body+sizeof(prefix)-1,len); id[len]='\0';
    if(strlen(id)!=len || !valid(id,1)) goto end;
    int files=openat(dir,"files",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(files<0) goto end;
    struct stat info;
    ok=fstatat(files,"Info.plist",&info,AT_SYMLINK_NOFOLLOW)==0 && S_ISREG(info.st_mode) && info.st_nlink==1;
    close(files);
end:
    close(fd);
    if(!ok) { close(dir); errno=EINVAL; return -1; }
    return dir;
}
int WCMRecycleInspect(int root, const char *name, char *identifier, unsigned long capacity) {
    if(!identifier || !capacity) { errno=EINVAL; return -1; }
    int dir=inspect_open(root,name,identifier,(size_t)capacity);
    if(dir<0) return -1;
    close(dir); return 0;
}
int WCMRecycleRestore(int root, int destination, const char *name, WCMCancel cancel, void *ctx) {
    char id[201]; int dir=inspect_open(root,name,id,sizeof id);
    if(dir<0) return -1;
    int files=openat(dir,"files",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(files<0) { close(dir); return -1; }
    if(cancel && cancel(ctx)) { close(files); close(dir); errno=ECANCELED; return -1; }
    /* Exclusive mkdir cannot overwrite an existing real directory, file or symlink.
       A failed copy may leave a partial directory: never delete a target automatically. */
    if(mkdirat(destination,id,0700)<0) { close(files); close(dir); return -1; }
    int out=openat(destination,id,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(out<0) { close(files); close(dir); return -1; }
    int result=copytree(files,out,0,cancel,ctx);
    if(!result && (fsync(out)<0 || fsync(destination)<0)) result=-1;
    int saved=errno; close(out); close(files); close(dir); errno=saved; return result;
}
/* Delete entries only from held descriptors; never follow symlinks. */
static int empty_dir(int fd, int depth) {
    if(depth>64) { errno=ELOOP; return -1; }
    int duplicate=dup(fd); if(duplicate<0) return -1;
    DIR *dir=fdopendir(duplicate); if(!dir) { close(duplicate); return -1; }
    struct dirent *ent; int result=0; errno=0;
    while((ent=readdir(dir))) {
        if(!strcmp(ent->d_name,".") || !strcmp(ent->d_name,"..")) { errno=0; continue; }
        struct stat st;
        if(fstatat(fd,ent->d_name,&st,AT_SYMLINK_NOFOLLOW)<0) { result=-1; break; }
        if(S_ISDIR(st.st_mode)) {
            int child=openat(fd,ent->d_name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
            if(child<0) { result=-1; break; }
            struct stat actual, parent;
            if(fstat(child,&actual)<0 || fstat(fd,&parent)<0 || actual.st_dev!=st.st_dev || actual.st_ino!=st.st_ino ||
               actual.st_dev!=parent.st_dev) {
                close(child); errno=EINVAL; result=-1; break;
            }
            result=empty_dir(child,depth+1); close(child);
            if(result || unlinkat(fd,ent->d_name,AT_REMOVEDIR)<0) { result=-1; break; }
        } else if(unlinkat(fd,ent->d_name,0)<0) { result=-1; break; }
        errno=0;
    }
    if(!result && errno) result=-1;
    int saved=errno; closedir(dir); errno=saved; return result;
}
int WCMRecycleRemove(int root, const char *name) {
    if(!transaction_name(name)) { errno=EINVAL; return -1; }
    int dir=openat(root,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(dir<0) return -1;
    struct stat a,b,parent;
    if(fstat(root,&parent)<0 || fstat(dir,&a)<0 || a.st_dev!=parent.st_dev ||
       fstatat(root,name,&b,AT_SYMLINK_NOFOLLOW)<0 || a.st_dev!=b.st_dev || a.st_ino!=b.st_ino) {
        close(dir); errno=EINVAL; return -1;
    }
    int result=empty_dir(dir,0);
    if(!result && (fstatat(root,name,&b,AT_SYMLINK_NOFOLLOW)<0 || a.st_dev!=b.st_dev || a.st_ino!=b.st_ino ||
                   unlinkat(root,name,AT_REMOVEDIR)<0)) result=-1;
    int saved=errno; close(dir); errno=saved; return result;
}
