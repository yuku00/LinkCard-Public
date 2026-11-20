#ifndef WU_STORAGE_MIGRATION_H
#define WU_STORAGE_MIGRATION_H
/* Runtime-only migration. No source writes, no cleanup or replacement of existing trees.
 * Checks detect observed changes, not a snapshot against uncooperative writers. */
#include "WUBackupTar.h"
#if defined(__APPLE__)
#include <copyfile.h>
#else
#include <sys/syscall.h>
#endif

static int wu_storage_metadata(int source, int target) {
#if defined(__APPLE__)
    // Preserve ACLs, stat metadata and extended attributes (including protection metadata).
    return fcopyfile(source,target,NULL,COPYFILE_METADATA)==0;
#else
    struct stat s; return !fstat(source,&s) && !fchmod(target,s.st_mode&0777);
#endif
}

typedef struct { uint64_t version, device, inode, extraDevice, extraInode; } WUStorageReceipt;
/* Only fixed strings and integer codes; no paths, names, or user content. */
typedef struct { const char *stage; const char *status; int error; } WUStorageDiagnostic;
static WUStorageDiagnostic wu_storage_diagnostic;
static void wu_storage_diag(const char *stage, const char *status, int error) {
    if(!wu_storage_diagnostic.stage) wu_storage_diagnostic=(WUStorageDiagnostic){stage,status,error};
}
static int wu_storage_directory(int parent, const char *name) {
    return openat(parent,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
}
static int wu_storage_absent(int parent, const char *name) {
    struct stat s; return fstatat(parent,name,&s,AT_SYMLINK_NOFOLLOW)<0 && errno==ENOENT;
}
static int wu_storage_regular(int parent, const char *name) {
    struct stat s; return !fstatat(parent,name,&s,AT_SYMLINK_NOFOLLOW) && S_ISREG(s.st_mode);
}
/* compare=0 copies to an exclusive tree; compare=1 rereads every byte and checks
 * both inventories, rejecting links and special files even in empty directories. */
static int wu_storage_tree(int source, int target, int compare, unsigned depth) {
    if(depth>64) return 0;
    struct stat before,after; if(fstat(source,&before) || !S_ISDIR(before.st_mode)) return 0;
    int scan=openat(source,".",O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    DIR *dir=scan>=0?fdopendir(scan):NULL; if(!dir) { if(scan>=0) close(scan); return 0; }
    int ok=1; size_t count=0; struct dirent *entry;
    for(;;) {
        errno=0; entry=readdir(dir); if(!entry) { if(errno) ok=0; break; }
        const char *name=entry->d_name; if(!strcmp(name,".") || !strcmp(name,"..")) continue;
        count++; struct stat a,b,current; int in=-1,out=-1;
        if(fstatat(source,name,&a,AT_SYMLINK_NOFOLLOW) || (!S_ISREG(a.st_mode) && !S_ISDIR(a.st_mode))) { ok=0; break; }
        in=openat(source,name,O_RDONLY|O_NOFOLLOW|(S_ISDIR(a.st_mode)?O_DIRECTORY:0));
        if(in<0 || fstat(in,&current) || !wu_tar_same(&a,&current)) { if(in>=0) close(in); ok=0; break; }
        if(S_ISDIR(a.st_mode)) {
            if(!compare && mkdirat(target,name,0700)) ok=0;
            if(ok) out=wu_storage_directory(target,name);
            if(out<0 || !wu_storage_tree(in,out,compare,depth+1)) ok=0;
        } else {
            out=openat(target,name,compare?(O_RDONLY|O_NOFOLLOW):(O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW),0600);
            if(out<0 || fstat(out,&b) || !S_ISREG(b.st_mode) || (compare && a.st_size!=b.st_size)) ok=0;
            char bytes[65536],check[65536]; off_t offset=0;
            while(ok && offset<a.st_size) {
                size_t n=(uint64_t)(a.st_size-offset)<sizeof(bytes)?(size_t)(a.st_size-offset):sizeof(bytes);
                ssize_t got=pread(in,bytes,n,offset); if(got<0 && errno==EINTR) continue;
                if(got!=(ssize_t)n) { ok=0; break; }
                if(!compare && !wu_tar_write(out,bytes,n)) { ok=0; break; }
                if(pread(out,check,n,offset)!=(ssize_t)n || memcmp(bytes,check,n)) { ok=0; break; }
                offset+=(off_t)n;
            }
            if(ok && !compare && (!wu_storage_metadata(in,out) || fsync(out))) ok=0;
        }
        if(fstat(in,&current) || !wu_tar_same(&a,&current) || fstatat(source,name,&current,AT_SYMLINK_NOFOLLOW) || !wu_tar_same(&a,&current)) ok=0;
        close(in); if(out>=0 && close(out)) ok=0; if(!ok) break;
    }
    closedir(dir);
    if(ok && compare) {
        scan=openat(target,".",O_RDONLY|O_DIRECTORY|O_NOFOLLOW); dir=scan>=0?fdopendir(scan):NULL;
        if(!dir) { if(scan>=0) close(scan); ok=0; }
        else { size_t other=0; for(;;) { errno=0; entry=readdir(dir); if(!entry) { if(errno) ok=0; break; } if(strcmp(entry->d_name,".") && strcmp(entry->d_name,"..")) other++; } if(other!=count) ok=0; closedir(dir); }
    }
    if(fstat(source,&after) || !wu_tar_same(&before,&after)) ok=0;
    if(ok && !compare && !wu_storage_metadata(source,target)) ok=0;
    return ok;
}
/* Strict directory-only evidence: zero regular files, no links/special files,
 * unreadable entries or observed identity changes. Never interpret an I/O error as empty. */
static int wu_storage_directories_only(int root, unsigned depth) {
    if(depth>64) return 0;
    struct stat before,after;
    if(fstat(root,&before) || !S_ISDIR(before.st_mode)) return 0;
    int scan=openat(root,".",O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    DIR *dir=scan>=0?fdopendir(scan):NULL;
    if(!dir) { if(scan>=0) close(scan); return 0; }
    int ok=1; struct dirent *entry;
    for(;;) {
        errno=0; entry=readdir(dir); if(!entry) { if(errno) ok=0; break; }
        const char *name=entry->d_name;
        if(!strcmp(name,".") || !strcmp(name,"..")) continue;
        struct stat a,b;
        if(fstatat(root,name,&a,AT_SYMLINK_NOFOLLOW) || !S_ISDIR(a.st_mode)) { ok=0; break; }
        int child=wu_storage_directory(root,name);
        ok=child>=0 && !fstat(child,&b) && wu_tar_same(&a,&b) && wu_storage_directories_only(child,depth+1);
        if(child>=0) close(child);
        if(!ok || fstatat(root,name,&b,AT_SYMLINK_NOFOLLOW) || !wu_tar_same(&a,&b)) { ok=0; break; }
    }
    closedir(dir);
    return ok && !fstat(root,&after) && wu_tar_same(&before,&after);
}
static int wu_storage_receipt(int support, WUStorageReceipt *r) {
    memset(r,0,sizeof(*r)); r->version=1; struct stat s;
    if(fstatat(support,"WeChatUnified",&s,AT_SYMLINK_NOFOLLOW)) { int e=errno; wu_storage_diag("legacy_main_stat","errno",e); return 0; }
    if(!S_ISDIR(s.st_mode)) { wu_storage_diag("legacy_main_stat","not_directory",0); return 0; }
    r->device=(uint64_t)s.st_dev; r->inode=(uint64_t)s.st_ino;
    if(!fstatat(support,"WeChatUnifiedEmoticons",&s,AT_SYMLINK_NOFOLLOW)) {
        if(!S_ISDIR(s.st_mode)) { wu_storage_diag("legacy_extra_stat","not_directory",0); return 0; }
        r->extraDevice=(uint64_t)s.st_dev; r->extraInode=(uint64_t)s.st_ino;
    } else if(errno!=ENOENT) { int e=errno; wu_storage_diag("legacy_extra_stat","errno",e); return 0; }
    return 1;
}
static int wu_storage_commit(int documents) {
#if defined(__APPLE__)
    return renameatx_np(documents,".WUStorage-migration",documents,"WeChatUnifiedStorage",RENAME_EXCL)==0;
#elif defined(SYS_renameat2)
    return syscall(SYS_renameat2,documents,".WUStorage-migration",documents,"WeChatUnifiedStorage",1)==0;
#else
    (void)documents; errno=ENOTSUP; return 0; /* Never fall back to replacing rename(). */
#endif
}
/* A missing parent is fresh only when lstat also reports ENOENT (not a dangling link). */
static int wu_storage_empty_source(const char *path, int support) {
    if(support>=0) return wu_storage_absent(support,"WeChatUnified") && wu_storage_absent(support,"WeChatUnifiedEmoticons");
    struct stat s;
    return path && lstat(path,&s)<0 && errno==ENOENT;
}
/* Returns a read-only descriptor for the committed envelope, or -1.
 * A valid committed target is authoritative; source identities are provenance only.
 * Failed stages are preserved, never resumed or removed automatically. */
static int wu_storage_prepare(const char *supportPath, int documents, const char **failure) {
    wu_storage_diagnostic=(WUStorageDiagnostic){0};
    WUStorageReceipt receipt={0},again;
    int support=-1, source=-1, extra=-1, stage=-1, target=-1, fresh=0, remnants=0;
    if(!wu_storage_absent(documents,"WeChatUnifiedStorage")) {
        *failure="Documents 已有目标但迁移凭据或数据根不匹配；已保护，未覆盖";
        target=wu_storage_directory(documents,"WeChatUnifiedStorage"); if(target<0) { int e=errno; wu_storage_diag("target_open","errno",e); goto failed; }
        int fd=openat(target,".wu-storage-v1",O_RDONLY|O_NOFOLLOW|O_NONBLOCK); struct stat s;
        int valid=fd>=0;
        if(!valid) { int e=errno; wu_storage_diag("target_receipt_open","errno",e); }
        if(valid && fstat(fd,&s)) { int e=errno; wu_storage_diag("target_receipt_stat","errno",e); valid=0; }
        if(valid && (!S_ISREG(s.st_mode) || s.st_size!=sizeof(receipt))) { wu_storage_diag("target_receipt_validate","invalid_type_or_size",0); valid=0; }
        if(valid) { ssize_t n=read(fd,&receipt,sizeof(receipt)); if(n<0) { int e=errno; wu_storage_diag("target_receipt_read","errno",e); valid=0; } else if(n!=sizeof(receipt)) { wu_storage_diag("target_receipt_read","short_read",0); valid=0; } }
        if(fd>=0) close(fd);
        /* v1: migrated legacy roots; v2: fresh installation, no legacy identities. */
        /* v3 records directory-only data loss, not recovered files. */
        valid=valid && (((receipt.version==1 || receipt.version==3) && receipt.inode && (receipt.extraInode || !receipt.extraDevice)) ||
                       (receipt.version==2 && !receipt.device && !receipt.inode && !receipt.extraDevice && !receipt.extraInode));
        if(!valid) wu_storage_diag("target_receipt_validate","invalid_fields",0);
        int main=wu_storage_directory(target,"WeChatUnified");
        if(main<0 && valid) { int e=errno; wu_storage_diag("target_main_open","errno",e); }
        int other=receipt.extraInode?wu_storage_directory(target,"WeChatUnifiedEmoticons"):-1;
        int otherError=other<0?errno:0;
        if(valid && receipt.extraInode && other<0) wu_storage_diag("target_extra_open","errno",otherError);
        int mainValid=valid && main>=0 && (wu_storage_regular(main,"config.json") || wu_storage_regular(main,"backup.json"));
        if(valid && main>=0 && !mainValid) wu_storage_diag("target_main_validate","no_eligible_config",0);
        valid=mainValid && (!receipt.extraInode || other>=0);
        if(main>=0) close(main); if(other>=0) close(other);
        if(!valid) goto failed;
        *failure=NULL; return target;
    }
    *failure="源目录不可读、缺损或不是普通目录；未创建空数据";
    if(!supportPath) { wu_storage_diag("support_url","unavailable",0); goto failed; }
    support=open(supportPath,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if(support<0 && errno!=ENOENT) { int e=errno; wu_storage_diag("support_open","errno",e); goto failed; }
    fresh=wu_storage_empty_source(supportPath,support);
    if(fresh) receipt.version=2;
    else {
        if(support<0) { wu_storage_diag("fresh_parent_probe","not_confirmed_absent",0); goto failed; }
        if(!wu_storage_receipt(support,&receipt)) goto failed;
        source=wu_storage_directory(support,"WeChatUnified"); if(source<0) { int e=errno; wu_storage_diag("legacy_main_open","errno",e); goto failed; }
        if(receipt.extraInode) { extra=wu_storage_directory(support,"WeChatUnifiedEmoticons"); if(extra<0) { int e=errno; wu_storage_diag("legacy_extra_open","errno",e); goto failed; } }
        if(!wu_storage_regular(source,"config.json") && !wu_storage_regular(source,"backup.json")) {
            *failure="旧目录无有效配置且仍有文件、链接或不可读内容；已保护，未当作空数据重建";
            if(!wu_storage_directories_only(source,0)) { wu_storage_diag("legacy_main_scan","not_directory_only_or_unreadable",0); goto failed; }
            if(extra>=0 && !wu_storage_directories_only(extra,0)) { wu_storage_diag("legacy_extra_scan","not_directory_only_or_unreadable",0); goto failed; }
            remnants=1;
        }
    }
    *failure="发现未完成迁移、目录不可写或空间不足；已保护并保留源及暂存目录";
    if(mkdirat(documents,".WUStorage-migration",0700)) { int e=errno; wu_storage_diag("stage_create","errno",e); goto failed; }
    stage=wu_storage_directory(documents,".WUStorage-migration"); if(stage<0) { int e=errno; wu_storage_diag("stage_open","errno",e); goto failed; }
    if(mkdirat(stage,"WeChatUnified",0700)) { int e=errno; wu_storage_diag("stage_main_create","errno",e); goto failed; }
    target=wu_storage_directory(stage,"WeChatUnified"); if(target<0) { int e=errno; wu_storage_diag("stage_main_open","errno",e); goto failed; }
    *failure="复制或逐文件校验失败（文件变化、链接、不可读、空间不足）；未提交，旧数据保留";
    if(fresh || remnants) {
        /* Persist defaults before the receipt so restart before the first save is safe. */
        const char defaults[]="{\"schema\":1,\"enabled\":false,\"words\":\"\"}";
        int fd=openat(target,"config.json",O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
        if(fd<0) { int e=errno; wu_storage_diag("defaults_create","errno",e); goto failed; }
        char check[sizeof(defaults)-1];
        int ok=wu_tar_write(fd,defaults,sizeof(defaults)-1) && fsync(fd)==0 &&
            pread(fd,check,sizeof(check),0)==sizeof(check) && !memcmp(check,defaults,sizeof(check));
        if(close(fd)) ok=0;
        if(!ok) { wu_storage_diag("defaults_write_verify","io_or_mismatch",0); goto failed; }
    } else {
        if(!wu_storage_tree(source,target,0,0)) { wu_storage_diag("main_copy","io_or_validation_failed",0); goto failed; }
        if(!wu_storage_tree(source,target,1,0)) { wu_storage_diag("main_verify","io_or_validation_failed",0); goto failed; }
    }
    close(target); target=-1;
    if(extra>=0) {
        if(mkdirat(stage,"WeChatUnifiedEmoticons",0700)) { int e=errno; wu_storage_diag("stage_extra_create","errno",e); goto failed; }
        target=wu_storage_directory(stage,"WeChatUnifiedEmoticons");
        if(target<0) { int e=errno; wu_storage_diag("stage_extra_open","errno",e); goto failed; }
        if(!remnants && !wu_storage_tree(extra,target,0,0)) { wu_storage_diag("extra_copy","io_or_validation_failed",0); goto failed; }
        if(!remnants && !wu_storage_tree(extra,target,1,0)) { wu_storage_diag("extra_verify","io_or_validation_failed",0); goto failed; }
        close(target); target=-1;
    }
    /* Final whole-tree pass catches changes to early files while later files copied. */
    target=wu_storage_directory(stage,"WeChatUnified");
    if(target<0) { int e=errno; wu_storage_diag("final_main_open","errno",e); goto failed; }
    if(remnants ? !wu_storage_directories_only(source,0) : (!fresh && !wu_storage_tree(source,target,1,0))) { wu_storage_diag("final_main_verify","io_or_validation_failed",0); goto failed; }
    close(target); target=-1;
    if(extra>=0) {
        target=wu_storage_directory(stage,"WeChatUnifiedEmoticons");
        if(target<0) { int e=errno; wu_storage_diag("final_extra_open","errno",e); goto failed; }
        if(remnants ? !wu_storage_directories_only(extra,0) : !wu_storage_tree(extra,target,1,0)) { wu_storage_diag("final_extra_verify","io_or_validation_failed",0); goto failed; }
        close(target); target=-1;
    }
    if(fresh) { if(!wu_storage_empty_source(supportPath,support)) { wu_storage_diag("fresh_recheck","not_confirmed_absent",0); goto failed; } }
    else if(!wu_storage_receipt(support,&again)) goto failed;
    else if(memcmp(&receipt,&again,sizeof(receipt))) { wu_storage_diag("legacy_identity_recheck","changed",0); goto failed; }
    if(remnants) receipt.version=3; /* Explicit loss provenance; source remains untouched. */
    int marker=openat(stage,".wu-storage-v1",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(marker<0) { int e=errno; wu_storage_diag("receipt_create","errno",e); goto failed; }
    int valid=wu_tar_write(marker,&receipt,sizeof(receipt)) && fsync(marker)==0;
    if(close(marker)) valid=0; if(!valid) { wu_storage_diag("receipt_write_sync","io_failed",0); goto failed; }
    /* Directory fsync is best effort on iOS; this is not a power-loss durability claim. */
    fsync(stage);
    *failure="目标发生冲突或系统不支持无覆盖原子提交；已保护，未覆盖任何目标";
    struct stat held,named;
    if(fstat(stage,&held)) { int e=errno; wu_storage_diag("stage_identity_fd","errno",e); goto failed; }
    if(fstatat(documents,".WUStorage-migration",&named,AT_SYMLINK_NOFOLLOW)) { int e=errno; wu_storage_diag("stage_identity_name","errno",e); goto failed; }
    if(!wu_tar_same(&held,&named)) { wu_storage_diag("stage_identity","changed",0); goto failed; }
    if(!wu_storage_commit(documents)) { int e=errno; wu_storage_diag("commit","errno",e); goto failed; }
    fsync(documents); if(source>=0) close(source); if(extra>=0) close(extra); if(support>=0) close(support);
    *failure=NULL; return stage;
failed:
    if(target>=0) close(target); if(stage>=0) close(stage); if(extra>=0) close(extra); if(source>=0) close(source); if(support>=0) close(support); return -1;
}
#endif
