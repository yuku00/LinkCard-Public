#ifndef WU_STORAGE_SELECTION_H
#define WU_STORAGE_SELECTION_H
/* Included after WUStorageMigration.h. All objects are created exclusively;
 * an interrupted attempt is preserved and never resumed as another attempt. */
#define WU_SELECTION_POINTER ".WUStorage-selection-v1"
#define WU_SELECTION_PREFIX "WeChatUnifiedStorage-New-"
static int wu_selection_name(const char *id, char *name, size_t size) {
    if(!id || strlen(id)!=36) return 0;
    for(int i=0;i<36;i++) {
        char c=id[i];
        if(i==8 || i==13 || i==18 || i==23) { if(c!='-') return 0; }
        else if(!((c>='0' && c<='9') || (c>='A' && c<='F'))) return 0;
    }
    return snprintf(name,size,WU_SELECTION_PREFIX "%s",id)>0 && size>strlen(WU_SELECTION_PREFIX)+36;
}
/* 1 = valid selection, 0 = explicitly absent, -1 = error/invalid. */
static int wu_selection_open(int docs, char *name, size_t size) {
    int fd=openat(docs,WU_SELECTION_POINTER,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);
    if(fd<0) return errno==ENOENT?0:-1;
    struct stat st; char id[37]={0};
    int ok=!fstat(fd,&st) && S_ISREG(st.st_mode) && st.st_size==36 &&
        read(fd,id,36)==36 && wu_selection_name(id,name,size);
    if(close(fd)) ok=0;
    if(!ok) return -1;
    int root=wu_storage_directory(docs,name);
    if(root<0) return -1;
    WUStorageReceipt receipt={0};
    fd=openat(root,".wu-storage-v1",O_RDONLY|O_NOFOLLOW|O_NONBLOCK);
    ok=fd>=0 && !fstat(fd,&st) && S_ISREG(st.st_mode) && st.st_size==sizeof(receipt) &&
        read(fd,&receipt,sizeof(receipt))==sizeof(receipt) && receipt.version==4 &&
        !receipt.device && !receipt.inode && !receipt.extraDevice && !receipt.extraInode;
    if(fd>=0 && close(fd)) ok=0;
    int main=wu_storage_directory(root,"WeChatUnified");
    if(main<0 || (!wu_storage_regular(main,"config.json") && !wu_storage_regular(main,"backup.json"))) ok=0;
    if(main>=0) close(main);
    close(root); return ok?1:-1;
}
/* Only available for the specific unmarked-target error. Recheck at confirmation;
 * permission errors, invalid markers, missing target and existing selection all block. */
static int wu_selection_create(int docs, const char *id) {
    char name[128], selected[128];
    if(!wu_selection_name(id,name,sizeof(name))) { errno=EINVAL; return 0; }
    if(wu_selection_open(docs,selected,sizeof(selected))!=0) { errno=EEXIST; return 0; }
    int old=wu_storage_directory(docs,"WeChatUnifiedStorage");
    if(old<0) return 0;
    struct stat original, named, current;
    int probe=openat(old,".wu-storage-v1",O_RDONLY|O_NOFOLLOW|O_NONBLOCK);
    int missing=probe<0 && errno==ENOENT;
    if(probe>=0) close(probe);
    if(!missing || fstat(old,&original) ||
       fstatat(docs,"WeChatUnifiedStorage",&named,AT_SYMLINK_NOFOLLOW) ||
       !wu_tar_same(&original,&named)) { close(old); errno=EEXIST; return 0; }
    if(mkdirat(docs,name,0700)) { close(old); return 0; }
    int root=wu_storage_directory(docs,name), main=-1, fd=-1, ok=0;
    if(root<0) { close(old); return 0; }
    if(mkdirat(root,"WeChatUnified",0700)) goto done;
    main=wu_storage_directory(root,"WeChatUnified"); if(main<0) goto done;
    const char defaults[]="{\"schema\":1,\"enabled\":false,\"words\":\"\"}";
    fd=openat(main,"config.json",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(fd<0) goto done;
    int wrote=wu_tar_write(fd,defaults,sizeof(defaults)-1) && !fsync(fd);
    if(close(fd)) wrote=0; fd=-1; if(!wrote) goto done;
    fsync(main);
    WUStorageReceipt receipt={4,0,0,0,0};
    fd=openat(root,".wu-storage-v1",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(fd<0) goto done;
    wrote=wu_tar_write(fd,&receipt,sizeof(receipt)) && !fsync(fd);
    if(close(fd)) wrote=0; fd=-1; if(!wrote) goto done;
    fd=openat(root,".wu-selection",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(fd<0) goto done;
    wrote=wu_tar_write(fd,id,36) && !fsync(fd);
    if(close(fd)) wrote=0; fd=-1; if(!wrote) goto done;
    fsync(root);
    /* Refuse an observed replacement, modification or newly added receipt. */
    if(fstat(old,&current) || !wu_tar_same(&original,&current) ||
       fstatat(docs,"WeChatUnifiedStorage",&named,AT_SYMLINK_NOFOLLOW) ||
       !wu_tar_same(&original,&named) || !wu_storage_absent(old,".wu-storage-v1")) goto done;
    /* linkat publishes only once and cannot replace a concurrent pointer. */
    if(linkat(root,".wu-selection",docs,WU_SELECTION_POINTER,0)) goto done;
    fsync(docs); ok=1;
done:
    if(fd>=0) close(fd); if(main>=0) close(main); close(root); close(old); return ok;
}
#endif
