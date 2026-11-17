#import "WUStorage.h"
#import "WUStorageMigration.h"
static NSURL *envelope;
static NSString *recoveryNotice;
static NSString *failure=@"插件存储尚未安全初始化";
BOOL WUStorageInitialize(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        (void)wu_backup_tar;
        NSFileManager *fm=NSFileManager.defaultManager;
        // Keep the legacy leaf unresolved: a dangling/replaced link is not a fresh install.
        NSURL *support=[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *documents=[[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByResolvingSymlinksInPath];
        if(!documents) { failure=@"无法定位 Documents；插件存储已保护"; return; }
        int dest=open(documents.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
        const char *reason="无法打开 Documents；未创建空数据";
        // The core checks a committed target before attempting to open any legacy source.
        int result=dest>=0?wu_storage_prepare(support.fileSystemRepresentation,dest,&reason):-1;
        if(dest>=0) close(dest);
        if(result<0) { failure=[NSString stringWithUTF8String:reason]; return; }
        WUStorageReceipt receipt={0};
        int marker=openat(result,".wu-storage-v1",O_RDONLY|O_NOFOLLOW);
        if(marker>=0) {
            if(read(marker,&receipt,sizeof(receipt))==sizeof(receipt) && receipt.version==3)
                recoveryNotice=@"旧插件目录只剩空目录，没有任何文件。原配置、主题资源和语音未找回；旧目录残骸已原样保留。已在 Documents/WeChatUnifiedStorage 建立新的禁用默认配置，请从独立备份恢复或重新导入资源。这不是文件恢复。";
            close(marker);
        }
        close(result); envelope=[documents URLByAppendingPathComponent:@"WeChatUnifiedStorage" isDirectory:YES]; failure=nil;
    });
    return envelope!=nil;
}
NSURL *WUStorageEnvelope(void) { return envelope; }
NSURL *WUStorageRoot(void) { return [envelope URLByAppendingPathComponent:@"WeChatUnified" isDirectory:YES]; }
NSURL *WUStorageEmoticons(void) { return [envelope URLByAppendingPathComponent:@"WeChatUnifiedEmoticons" isDirectory:YES]; }
NSString *WUStorageFailure(void) { return failure; }
NSString *WUStorageRecoveryNotice(void) { return recoveryNotice; }
