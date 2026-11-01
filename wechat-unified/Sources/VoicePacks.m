#import "VoicePacks.h"
#import "VoicePackLogic.h"
#import "OfflineVoice.h"
#import "WU.h"
#import <AVFoundation/AVFoundation.h>
#include <stdlib.h>
#include <string.h>
@implementation WUVoicePackBinding
@end
static dispatch_queue_t Queue(void) { static dispatch_queue_t q; static dispatch_once_t once; dispatch_once(&once,^{ q=dispatch_queue_create("WU.voice-packs",DISPATCH_QUEUE_SERIAL); }); return q; }
static NSData *Wave(NSData *data) {
    WUOfflinePCM pcm={0}; if(WUOfflineDecode(data.bytes,data.length,NULL,NULL,&pcm)) return nil;
    uint32_t bytes=(uint32_t)pcm.frames*2, total=36+bytes, rate=pcm.rate, speed=rate*2, fmtSize=16;
    uint16_t fmt=1, channels=1, align=2, bits=16;
    NSMutableData *wave=[NSMutableData dataWithLength:44+bytes]; uint8_t *p=wave.mutableBytes;
    memcpy(p,"RIFF",4); memcpy(p+4,&total,4); memcpy(p+8,"WAVEfmt ",8); memcpy(p+16,&fmtSize,4); memcpy(p+20,&fmt,2); memcpy(p+22,&channels,2); memcpy(p+24,&rate,4); memcpy(p+28,&speed,4); memcpy(p+32,&align,2); memcpy(p+34,&bits,2); memcpy(p+36,"data",4); memcpy(p+40,&bytes,4);
    int16_t *samples=(int16_t *)(p+44); for(size_t i=0;i<pcm.frames;i++) samples[i]=(int16_t)(pcm.samples[i]*32768.0f);
    free(pcm.samples); return wave;
}
@interface WUVoicePacksController : UITableViewController <AVAudioPlayerDelegate>
@property(nonatomic,strong) WUVoicePackBinding *binding;
@property(nonatomic,strong) WUVoicePackStore *store;
@property(nonatomic,strong) NSArray *rows;
@property(nonatomic,strong) NSMutableSet *submitted;
@property(nonatomic,strong) AVAudioPlayer *player;
@property(nonatomic,copy) NSString *playing;
@property(nonatomic,strong) id backgroundObserver;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NSProgress *cancellation;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL invalid;
@end
@implementation WUVoicePacksController
- (BOOL)current { return !self.invalid && self.binding.current && self.binding.current(); }
- (void)notice:(NSString *)s {
    if(![self current] || self.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"本地语音包" message:s preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)stop {
    [self.player stop]; self.player=nil;
    if(self.playing) { [self.store releaseResource:self.playing]; self.playing=nil; }
}
- (void)close { self.invalid=YES; [self.cancellation cancel]; [self stop]; [self.timer invalidate]; self.timer=nil; [self.navigationController.presentingViewController dismissViewControllerAnimated:NO completion:nil]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.cancellation=[NSProgress progressWithTotalUnitCount:1]; self.title=@"本账号本地语音包"; self.submitted=[NSMutableSet set];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithTitle:@"保存所选" style:UIBarButtonItemStylePlain target:self action:@selector(saveSelected)],[[UIBarButtonItem alloc] initWithTitle:@"停止试听" style:UIBarButtonItemStylePlain target:self action:@selector(stop)]];
    __weak typeof(self) weak=self;
    self.backgroundObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){ [weak close]; }];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t){ if(![weak current]) [weak close]; }]; [self reload];
}
- (void)dealloc { if(self.backgroundObserver) [NSNotificationCenter.defaultCenter removeObserver:self.backgroundObserver]; [self.timer invalidate]; [self.player stop]; if(self.playing) [self.store releaseResource:self.playing]; }
- (void)reload {
    if(![self current]) return; self.busy=YES;
    dispatch_async(Queue(),^{ NSError *error=nil; NSArray *rows=[self.store load:&error];
        dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; if(![self current]) return; self.rows=rows?:@[]; [self.tableView reloadData]; if(error) [self notice:error.localizedDescription]; });
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"仅所选就绪34类原始配对；外部文件导入尚未开放。试听完全离线，不发送。跨宿主版本仅可试听。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NSDictionary *r=self.rows[path.row];
    c.textLabel.text=r[@"name"]; c.detailTextLabel.numberOfLines=0;
    c.detailTextLabel.text=[NSString stringWithFormat:@"所选微信语音 · %@毫秒 · format %@\n来源版本 %@ · %@",r[@"ms"],r[@"format"],r[@"version"],[r[@"version"] isEqual:self.binding.version]?@"可确认单次发送":@"版本不同：不可发送，仅试听"];
    return c;
}
- (void)saveSelected {
    if(self.busy || ![self current]) return;
    NSDictionary *snapshot=self.binding.capture?self.binding.capture():nil;
    if(!snapshot) { [self notice:@"请返回聊天多选一条本会话已就绪语音，再打开本页；缺少真实数据、格式或版本时拒绝保存。"]; return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"保存所选原始语音" message:@"仅复制此条原始载荷及实际format/版本配对，不改宿主消息。限60秒，32条/32MiB。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder=@"语音名称（1—80字符）"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *wa=a; __block BOOL chosen=NO;
    [a addAction:[UIAlertAction actionWithTitle:@"离线验证并保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        if(chosen || self.busy || ![self current]) return; chosen=YES; self.busy=YES;
        NSString *name=[wa.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSUInteger gen=self.binding.generation;
        dispatch_async(Queue(),^{ NSError *error=nil; BOOL ok=[self.store saveData:snapshot[@"data"] format:snapshot[@"format"] version:snapshot[@"version"] name:name current:^BOOL{ return !self.cancellation.cancelled && WUContextGenerationSnapshot()==gen; } error:&error];
            dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; if(![self current]) return; if(ok) [self reload]; else [self notice:error.localizedDescription?:@"保存失败，旧包保留"]; });
        });
    }]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)edit:(NSDictionary *)row deleting:(BOOL)deleting {
    if(self.busy || ![self current]) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:deleting?@"删除自有语音包？":@"重命名" message:deleting?@"只删除本账号自有索引内副本，不动宿主源。正在试听/发送占用的资源拒绝删除。":nil preferredStyle:UIAlertControllerStyleAlert];
    if(!deleting) [a addTextFieldWithConfigurationHandler:^(UITextField *t){ t.text=row[@"name"]; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *wa=a; __block BOOL chosen=NO;
    [a addAction:[UIAlertAction actionWithTitle:deleting?@"删除副本":@"保存名称" style:deleting?UIAlertActionStyleDestructive:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        if(chosen || self.busy || ![self current]) return; chosen=YES; self.busy=YES;
        NSString *name=wa.textFields.firstObject.text; NSUInteger gen=self.binding.generation;
        dispatch_async(Queue(),^{ NSError *error=nil; BOOL (^valid)(void)=^BOOL{ return !self.cancellation.cancelled && WUContextGenerationSnapshot()==gen; };
            BOOL ok=deleting?[self.store remove:row[@"id"] current:valid error:&error]:[self.store rename:row[@"id"] name:name current:valid error:&error];
            dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; if(![self current]) return; if(ok) [self reload]; else [self notice:error.localizedDescription?:@"操作失败，旧数据保留"]; });
        });
    }]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)use:(NSDictionary *)row sending:(BOOL)sending {
    if(self.busy || ![self current]) return;
    if(sending && (![row[@"version"] isEqual:self.binding.version] || [self.submitted containsObject:row[@"id"]])) { [self notice:@"来源版本不同或本页已提交过此资源；未请求发送。跨重启不保证恰好一次。"]; return; }
    [self stop]; self.busy=YES;
    dispatch_async(Queue(),^{ NSError *error=nil; NSDictionary *held=[self.store acquire:row[@"id"] error:&error];
        NSData *wave=held && !sending?Wave(held[@"data"]):nil;
        WUVoiceForwardOperation *operation=held && sending?[[WUVoiceForwardOperation alloc] initWithData:held[@"data"] account:self.binding.account target:self.binding.target]:nil;
        dispatch_async(dispatch_get_main_queue(),^{
            self.busy=NO;
            if(![self current]) { if(held) [self.store releaseResource:held[@"id"]]; return; }
            if(!held) { [self notice:error.localizedDescription?:@"资源不可用"]; return; }
            self.playing=held[@"id"];
            if(!sending) {
                NSError *e=nil; self.player=wave?[[AVAudioPlayer alloc] initWithData:wave error:&e]:nil; self.player.delegate=self;
                if(![self.player play]) { [self stop]; [self notice:e.localizedDescription?:@"离线试听不可用，没有调用宿主发送"]; } return;
            }
            if(!WUVoicePackMatches(held,self.binding.version) || !operation.milliseconds) { [self stop]; [self notice:@"配对版本、格式或完整解码无效，拒绝发送"]; return; }
            UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认单次发送" message:[NSString stringWithFormat:@"来源：所选微信语音 %@\n名称：%@\n真实时长：%u毫秒\n账号：%@\n当前会话收件人：%@\n只请求一次，不保证送达，无自动重试；无跨重启恰好一次保证。",held[@"version"],held[@"name"],operation.milliseconds,self.binding.account,self.binding.target] preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){ [self stop]; }]];
            __block BOOL consumed=NO;
            [a addAction:[UIAlertAction actionWithTitle:@"向此会话请求发送一次" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
                if(consumed) return; consumed=YES;
                if(![self current] || ![self.playing isEqual:held[@"id"]] || [self.submitted containsObject:held[@"id"]]) { [self stop]; return; }
                [self.submitted addObject:held[@"id"]]; NSString *result=@"失败：未提交";
                @try { if(self.binding.send) result=self.binding.send(operation); } @catch(NSException *e) { result=@"未知：调用异常，不自动重试"; }
                [self stop];
                [self dismissViewControllerAnimated:YES completion:^{ [self notice:result]; }];
            }]]; [self presentViewController:a animated:YES completion:nil];
        });
    });
}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag { [self stop]; }
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error { [self stop]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if(self.busy || ![self current]) return;
    NSDictionary *row=self.rows[path.row];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:row[@"name"] message:@"来源：本账号手动所选微信语音；非AI，无联网TTS。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"离线试听" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self use:row sending:NO]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"确认发送至当前会话" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self use:row sending:YES]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"重命名" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self dismissViewControllerAnimated:YES completion:^{ [self edit:row deleting:NO]; }]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除自有副本" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){ [self dismissViewControllerAnimated:YES completion:^{ [self edit:row deleting:YES]; }]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
@end
BOOL WUIsVoicePacksController(UIViewController *controller) {
    return [controller isKindOfClass:UINavigationController.class] && [[(UINavigationController *)controller topViewController] isKindOfClass:WUVoicePacksController.class];
}
void WUShowVoicePacks(UIViewController *owner, WUVoicePackBinding *binding) {
    if(!binding.current || !binding.current() || owner.presentedViewController) return;
    NSURL *base=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByResolvingSymlinksInPath];
    WUVoicePacksController *v=[[WUVoicePacksController alloc] initWithStyle:UITableViewStyleInsetGrouped]; v.binding=binding;
    v.store=[[WUVoicePackStore alloc] initWithRoot:[base URLByAppendingPathComponent:@"WeChatUnified/VoicePacks" isDirectory:YES] account:binding.account];
    if(!v.store) return;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:v]; nav.modalInPresentation=YES;
    [owner presentViewController:nav animated:YES completion:nil];
}
