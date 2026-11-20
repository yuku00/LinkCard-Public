#import "WUStorage.h"
#import "WUStorageMigration.h"
#import "WUStorageSelection.h"
#import <dlfcn.h>
#import <mach-o/loader.h>

/* LC_UUID identifies the image containing this very function, not the host app.
 * Never expose the image path, and do not invent an identifier if it is absent. */
static NSString *WUStorageLoadedBuild(void) {
    Dl_info info;
    if(!dladdr((const void *)&WUStorageInitialize,&info) || !info.dli_fbase) return @"unavailable";
    const struct mach_header_64 *header=(const struct mach_header_64 *)info.dli_fbase;
    if(header->magic!=MH_MAGIC_64 || header->sizeofcmds>16*1024*1024) return @"unavailable";
    const uint8_t *cursor=(const uint8_t *)(header+1), *end=cursor+header->sizeofcmds;
    for(uint32_t i=0;i<header->ncmds && (size_t)(end-cursor)>=sizeof(struct load_command);i++) {
        const struct load_command *command=(const struct load_command *)cursor;
        if(command->cmdsize<sizeof(*command) || command->cmdsize>(size_t)(end-cursor)) break;
        if(command->cmd==LC_UUID && command->cmdsize>=sizeof(struct uuid_command)) {
            const struct uuid_command *uuid=(const struct uuid_command *)command;
            return [[[NSUUID alloc] initWithUUIDBytes:uuid->uuid] UUIDString] ?: @"unavailable";
        }
        cursor+=command->cmdsize;
    }
    return @"unavailable";
}
static NSString *diagnosticStage=@"initialization";
static NSString *diagnosticStatus=@"not_started";
static int diagnosticError;
static void WUStorageSetDiagnostic(const char *stage, const char *status, int error) {
    diagnosticStage=[NSString stringWithUTF8String:stage ?: "unknown"];
    diagnosticStatus=[NSString stringWithUTF8String:status ?: "unknown"];
    diagnosticError=error;
}
NSString *WUStorageDiagnosticSummary(void) {
    NSString *result=diagnosticError ? [NSString stringWithFormat:@"errno=%d",diagnosticError] : diagnosticStatus;
    return [NSString stringWithFormat:@"构建 UUID：%@\n阶段：%@\n状态：%@", WUStorageLoadedBuild(), diagnosticStage, result];
}
void WUStorageRecordConfigRootFailure(int error) { WUStorageSetDiagnostic("config_root_open", "errno", error); }
static NSURL *envelope;
static NSString *recoveryNotice;
static BOOL presentRecoveryNotice;
static NSString *failure=@"插件存储尚未安全初始化";
static BOOL mayCreateSeparate;
BOOL WUStorageMayCreateSeparate(void) { return mayCreateSeparate; }
BOOL WUStorageCreateSeparate(void) {
    if(!mayCreateSeparate) return NO;
    NSURL *documents=[[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByResolvingSymlinksInPath];
    if(!documents) return NO;
    int fd=open(documents.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if(fd<0) return NO;
    BOOL ok=wu_selection_create(fd,NSUUID.UUID.UUIDString.UTF8String);
    close(fd);
    mayCreateSeparate=NO;
    return ok;
}
BOOL WUStorageInitialize(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        (void)wu_backup_tar;
        NSFileManager *fm=NSFileManager.defaultManager;
        // Keep the legacy leaf unresolved: a dangling/replaced link is not a fresh install.
        NSURL *support=[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *documents=[[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByResolvingSymlinksInPath];
        if(!documents) { WUStorageSetDiagnostic("documents_url","unavailable",0); failure=@"无法定位存储目标；插件存储已保护"; return; }
        int dest=open(documents.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
        int destError=dest<0?errno:0;
        const char *reason="无法打开存储目标；未创建空数据";
        char selected[128]={0};
        int selection=dest>=0?wu_selection_open(dest,selected,sizeof(selected)):-1;
        if(dest>=0 && selection<0) {
            WUStorageSetDiagnostic("selection_validate","invalid_or_unreadable",0);
            failure=@"独立存储选择凭据无效或不可读；已保护，没有切换到其他目录";
            close(dest); return;
        }
        if(selection==1) {
            close(dest);
            envelope=[documents URLByAppendingPathComponent:[NSString stringWithUTF8String:selected] isDirectory:YES];
            // Confirmation already reports creation; selecting the same committed library is not a new event.
            recoveryNotice=@"正在使用用户确认创建的全新独立库；这不是历史数据恢复。原 Documents 目标和旧目录均保留，请从独立备份恢复或重新导入。";
            failure=nil; WUStorageSetDiagnostic("selection","ready",0); return;
        }
        // The core checks a committed target before attempting to open any legacy source.
        int result=dest>=0?wu_storage_prepare(support.fileSystemRepresentation,dest,&reason):-1;
        if(result<0 && dest>=0 && wu_storage_diagnostic.stage &&
           !strcmp(wu_storage_diagnostic.stage,"target_receipt_open") && wu_storage_diagnostic.error==ENOENT)
            mayCreateSeparate=YES;
        if(result>=0 && wu_selection_open(dest,selected,sizeof(selected))!=0) {
            close(result); result=-1; reason="存储选择发生变化或不可读；已保护，请重启后检查";
            WUStorageSetDiagnostic("selection_recheck","changed_or_unreadable",0);
        }
        if(dest<0) WUStorageSetDiagnostic("documents_open","errno",destError);
        else if(result<0 && ![diagnosticStage isEqual:@"selection_recheck"]) WUStorageSetDiagnostic(wu_storage_diagnostic.stage,wu_storage_diagnostic.status,wu_storage_diagnostic.error);
        if(dest>=0) close(dest);
        if(result<0) { failure=[NSString stringWithUTF8String:reason]; return; }
        WUStorageReceipt receipt={0};
        int marker=openat(result,".wu-storage-v1",O_RDONLY|O_NOFOLLOW);
        if(marker>=0) {
            if(read(marker,&receipt,sizeof(receipt))==sizeof(receipt) && receipt.version==3) {
                recoveryNotice=@"旧插件目录只剩空目录，没有任何文件。原配置、主题资源和语音未找回；旧目录残骸已原样保留。已建立新的禁用默认配置，请从独立备份恢复或重新导入资源。这不是文件恢复。";
                presentRecoveryNotice=YES;
            }
            close(marker);
        }
        close(result); envelope=[documents URLByAppendingPathComponent:@"WeChatUnifiedStorage" isDirectory:YES]; failure=nil;
        WUStorageSetDiagnostic("initialization","ready",0);
    });
    return envelope!=nil;
}
NSURL *WUStorageEnvelope(void) { return envelope; }
NSURL *WUStorageRoot(void) { return [envelope URLByAppendingPathComponent:@"WeChatUnified" isDirectory:YES]; }
NSURL *WUStorageEmoticons(void) { return [envelope URLByAppendingPathComponent:@"WeChatUnifiedEmoticons" isDirectory:YES]; }
NSString *WUStorageFailure(void) { return failure; }
NSString *WUStorageRecoveryNotice(void) { return recoveryNotice; }
BOOL WUStorageShouldPresentRecoveryNotice(void) { return presentRecoveryNotice; }
