#import "WUCapture.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdbool.h>
#import <string.h>
#import <stdlib.h>
#import <time.h>

#define SCENE_COUNT 10
#define SCENE_LIMIT 64
#define NAME_LIMIT 512
// Only copied names cross the callback boundary; never retain a Class pointer.
typedef struct { char name[NAME_LIMIT+1]; unsigned point; unsigned long sequence; } CaptureEvent;
typedef struct { CaptureEvent events[SCENE_LIMIT]; unsigned count, windowCount, marks; unsigned long full, limited, invalid; time_t window; } SceneCapture;
typedef struct { SceneCapture scenes[SCENE_COUNT]; unsigned scene; unsigned long sequence, contended; } CaptureSnapshot;
static pthread_mutex_t captureLock=PTHREAD_MUTEX_INITIALIZER;
static _Atomic(bool) active=false;
static _Atomic(unsigned long) contended=0;
static CaptureSnapshot capture;
static BOOL building;
// Main-thread session storage; reject whole snapshots once either budget is full.
static NSMutableArray<NSString *> *pageReports;
static NSUInteger pageReportLength, pageReportsDropped;
#define PAGE_REPORT_COUNT_LIMIT 4
#define PAGE_REPORT_LENGTH_LIMIT 262144
static bool WUPageCanAppend(size_t count, size_t length, size_t incoming) {
    return count<PAGE_REPORT_COUNT_LIMIT && length<=PAGE_REPORT_LENGTH_LIMIT && incoming<=PAGE_REPORT_LENGTH_LIMIT-length;
}
static NSString *finishedReport;
static const char *scenes[]={"未标记","聊天","聊天工具栏","搜索","表情","语音","服务与卡包","小程序","朋友圈","其他"};
static const char *points[]={"","聊天页 viewDidAppear: 原实现返回","聊天工具栏 didMoveToWindow 附着","搜索栏 layoutSubviews 在窗口","语音 setIsPlaying: 原实现返回","拍一拍回调入口","小程序 invokeInJsContext: 回调入口"};

void WUCaptureObserve(id object, unsigned point) {
    if(!object || point<1 || point>6 || !atomic_load_explicit(&active,memory_order_relaxed)) return;
    if(pthread_mutex_trylock(&captureLock)!=0) { atomic_fetch_add_explicit(&contended,1,memory_order_relaxed); return; }
    if(atomic_load_explicit(&active,memory_order_relaxed)) {
        SceneCapture *s=&capture.scenes[capture.scene];
        struct timespec ts; if(clock_gettime(CLOCK_MONOTONIC,&ts)!=0) { s->limited++; pthread_mutex_unlock(&captureLock); return; }
        if(s->window!=ts.tv_sec) { s->window=ts.tv_sec; s->windowCount=0; }
        if(s->windowCount>=20) s->limited++;
        else if(s->count>=SCENE_LIMIT) s->full++;
        else {
            s->windowCount++;
            const char *name=class_getName(object_getClass(object));
            size_t n=name?strnlen(name,NAME_LIMIT+1):0;
            if(!n || n>NAME_LIMIT) s->invalid++;
            else { CaptureEvent *e=&s->events[s->count++]; memcpy(e->name,name,n); e->name[n]=0; e->point=point; e->sequence=++capture.sequence; }
        }
    }
    pthread_mutex_unlock(&captureLock);
}
static NSString *RuntimeString(const char *s, size_t max) {
    if(!s) return @"（不可用）";
    size_t n=strnlen(s,max+1);
    if(n>max) return @"（超长已省略）";
    return [[NSString alloc] initWithBytes:s length:n encoding:NSUTF8StringEncoding] ?: @"（非 UTF-8 已省略）";
}
static void AppendMethods(NSMutableString *out, Class cls, BOOL meta) {
    unsigned count=0; Method *list=class_copyMethodList(meta?object_getClass(cls):cls,&count);
    unsigned limit=MIN(count,96u);
    [out appendFormat:@"  %@本类声明 %u，列出最多 %u%@：\n",meta?@"+ 类方法":@"- 实例方法",count,limit,count>limit?@"（截断）":@""];
    if(!list && count) { [out appendString:@"  （枚举失败）\n"]; return; }
    for(unsigned i=0;i<limit;i++) {
        if(out.length>=250000) { [out appendString:@"  报告总长度超限，剩余声明截断。\n"]; break; }
        [out appendFormat:@"  %@ %@ | 完整编码 %@\n",meta?@"+":@"-",RuntimeString(sel_getName(method_getName(list[i])),512),RuntimeString(method_getTypeEncoding(list[i]),2048)];
    }
    free(list);
}
static NSString *Report(const CaptureSnapshot *snapshot, BOOL stopped) {
    NSMutableString *out=[NSMutableString stringWithString:@"跨页面本地接口采集\n仅记录六个已有回调执行到采集点；方法声明不等于调用，事件不证明业务成功或因果；未捕获不代表不存在。真实类名、selector、完整编码及模块名可能含敏感信息，分享前须审阅。未有意读取对象字段、消息、账号、URL、参数或返回值；不自动上传。\n"];
    [out appendFormat:@"状态：%@；锁竞争丢弃至少 %lu（无法归场景）。各场景独立最多64条、每场景每秒最多20条。\n",stopped?@"已停止":@"运行中手动快照",snapshot->contended];
    NSMutableArray<NSString *> *unique=[NSMutableArray array]; BOOL classTruncated=NO; unsigned calls=0;
    for(unsigned scene=0;scene<SCENE_COUNT;scene++) {
        const SceneCapture *s=&snapshot->scenes[scene];
        [out appendFormat:@"\n【场景 %s】用户标记 %u 次；事件 %u；满额丢弃 %lu，限流丢弃 %lu，类名无效/过长丢弃 %lu。\n",scenes[scene],s->marks,s->count,s->full,s->limited,s->invalid];
        if(!s->count) [out appendString:@"未捕获事件：可能未经过、挂点未安装或被丢弃。\n"];
        for(unsigned i=0;i<s->count;i++) {
            const CaptureEvent *e=&s->events[i]; calls++;
            NSString *name=RuntimeString(e->name,NAME_LIMIT);
            [out appendFormat:@"序号 %lu | %@ | 接收者类 %@\n",e->sequence,RuntimeString(points[e->point],512),name];
            if(![unique containsObject:name]) { if(unique.count<24) [unique addObject:name]; else classTruncated=YES; }
        }
    }
    if(!calls) [out appendString:@"\n无调用事件。\n"];
    [out appendString:@"\n【观察到的类及本类声明：并非调用记录】最多24个接收者类、每条父类链8层、每类每种方法96个；超过上限或编码过长明确省略。模块仅文件名。后台按复制名称重新解析，动态类消失或同名重建可能无法解析或与观察时不同。\n"];
    if(classTruncated) [out appendString:@"接收者类超过24个，其余类声明截断。\n"];
    for(NSString *name in unique) {
        if(out.length>=250000) { [out appendString:@"报告总长度超限，其余类截断。\n"]; break; }
        Class cls=objc_lookUpClass(name.UTF8String);
        if(!cls) { [out appendFormat:@"\n类 %@：当前无法解析，声明未捕获。\n",name]; continue; }
        unsigned depth=0;
        for(;cls && depth<8;cls=class_getSuperclass(cls),depth++) {
            if(out.length>=250000) { [out appendString:@"报告总长度超限，剩余父类截断。\n"]; break; }
            const char *image=class_getImageName(cls); const char *base=image?strrchr(image,'/'):NULL;
            [out appendFormat:@"\n类 %@ | 父类 %@ | 模块 %@\n",RuntimeString(class_getName(cls),512),class_getSuperclass(cls)?RuntimeString(class_getName(class_getSuperclass(cls)),512):@"（无）",RuntimeString(base?base+1:image,512)];
            AppendMethods(out,cls,NO); AppendMethods(out,cls,YES);
        }
        if(cls && depth>=8) [out appendString:@"父类链超过8层，已截断。\n"];
    }
    [out appendString:@"\n【覆盖限制】仅聊天页、聊天工具栏、搜索栏、语音播放状态、拍一拍和小程序调用六个既有挂点；版本、启动保护或安装状态可导致未捕获。其他场景没有专用挂点。场景为用户手动标记，不证明页面归属；无全局拦截、调用栈或新增业务 Hook，不启用暂停功能。\n"];
    return out;
}

#import "WUPageGeometry.inc"

// User-authorized one-shot hierarchy; all UIKit access stays on main.
@interface WUPageNode : NSObject
@property(nonatomic,strong) id object;
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,weak) UIWindowScene *scene;
@property(nonatomic,copy) NSString *parent;
@property(nonatomic,assign) BOOL controller;
@end
@implementation WUPageNode @end

static void WUPageSnapshot(void (^done)(NSString *)) {
    NSCAssert(NSThread.isMainThread,@"main thread only");
    UIApplication *app=UIApplication.sharedApplication;
    if(@available(iOS 13.0, *)) {
        if(app.applicationState!=UIApplicationStateActive) { done(nil); return; }
        NSMutableString *out=[NSMutableString stringWithString:@"用户主动延迟页面类快照（本进程）\n场景和窗口序号仅为本次标记，不代表身份或目标。插件界面、系统在本应用内的窗口可能出现；可见性仅按 hidden/alpha 判断，不判断遮挡或屏幕位置；分批时层级可能变化。类名、层级与几何可能敏感：位置、尺寸和排列可间接暴露消息长度、数量、类型、界面状态及滚动位置，分享前审阅。精确 UIKit 及指定微信类名白名单记录 frame 与 bounds；宿主子类 getter 可能重写并产生副作用或异常，主线程分批采集可能卡顿；滚动视图仅记录 bounds.size 和边距，不记录滚动原点。不能推断调用或业务成功。\n"];
        NSMutableArray<WUPageNode *> *queue=[NSMutableArray array];
        __block NSUInteger sceneCount=0, windowCount=0, skipped=0;
        BOOL sceneCut=NO, windowCut=NO; NSUInteger scannedWindows=0;
        for(UIScene *scene in app.connectedScenes) {
            if(sceneCount>=16) { sceneCut=YES; break; }
            sceneCount++;
            if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
            UIWindowScene *ws=(UIWindowScene *)scene;
            for(UIWindow *w in ws.windows) {
                if(scannedWindows++>=64 || windowCount>=32) { windowCut=YES; break; }
                if(w.hidden || w.alpha<=0.01) continue;
                windowCount++;
                NSString *tag=[NSString stringWithFormat:@"场景%lu/窗口%lu",(unsigned long)sceneCount,(unsigned long)windowCount];
                [out appendFormat:@"\n%@ 窗口类 %@\n",tag,RuntimeString(class_getName(object_getClass(w)),NAME_LIMIT)];
                for(id obj in @[w.rootViewController ?: NSNull.null, w]) {
                    if(obj==NSNull.null) continue;
                    WUPageNode *n=[WUPageNode new]; n.object=obj; n.window=w; n.scene=ws; n.parent=tag; n.controller=(obj!=w); [queue addObject:n];
                }
            }
        }
        [out appendFormat:@"场景扫描上限16%@；窗口扫描上限64、可见窗口上限32%@；扫描 %lu 场景，采集 %lu 窗口。\n",sceneCut?@"（截断）":@"",windowCut?@"（截断）":@"",(unsigned long)sceneCount,(unsigned long)windowCount];
        __block NSUInteger index=0, serial=0;
        __block void (^step)(void);
        step=^{
            if(app.applicationState!=UIApplicationStateActive) { step=nil; done(nil); return; }
            NSUInteger end=MIN(index+32,queue.count);
            while(index<end) {
                WUPageNode *n=queue[index++]; UIWindow *w=n.window; UIWindowScene *ws=n.scene;
                if(!w || !ws || ws.activationState!=UISceneActivationStateForegroundActive || w.windowScene!=ws || w.hidden || w.alpha<=0.01) { skipped++; continue; }
                id obj=n.object;
                if(!n.controller) { UIView *v=obj; if(v.hidden || v.alpha<=0.01 || (v!=w && v.window!=w)) { skipped++; continue; } }
                NSString *tag=[NSString stringWithFormat:@"节点%lu",(unsigned long)++serial];
                [out appendFormat:@"%@ <- %@ | %@ %@\n",tag,n.parent,n.controller?@"控制器":@"视图",RuntimeString(class_getName(object_getClass(obj)),NAME_LIMIT)];
                if(!n.controller) WUPageAppendGeometry(out,obj);
                NSArray *groups;
                if(n.controller) { UIViewController *vc=obj; UIViewController *presented=vc.presentedViewController; groups=@[presented?@[presented]:@[],vc.childViewControllers]; }
                else groups=@[((UIView *)obj).subviews];
                for(NSArray *children in groups) for(id child in children) {
                    if(queue.count>=1024) { skipped++; break; }
                    WUPageNode *next=[WUPageNode new]; next.object=child; next.window=w; next.scene=ws; next.parent=tag; next.controller=n.controller; [queue addObject:next];
                }
            }
            if(index<queue.count) { dispatch_async(dispatch_get_main_queue(),step); return; }
            [out appendFormat:@"\n节点上限1024；未处理/隐藏/变化或超限分支至少 %lu；上限可能截断整棵子树。控制器树不保证控制器当前可见。\n",(unsigned long)skipped];
            NSString *result=[out copy]; step=nil; done(result);
        };
        dispatch_async(dispatch_get_main_queue(),step);
    } else { done(nil); }
}

static NSString *pageStatus;
@interface WUCaptureController : UIViewController @end
@implementation WUCaptureController
- (void)refresh {
    BOOL running=atomic_load(&active);
    self.title=@"跨页面接口采集";
    self.navigationItem.leftItemsSupplementBackButton=YES;
    UIBarButtonItem *page=[[UIBarButtonItem alloc] initWithTitle:@"页面类" style:UIBarButtonItemStylePlain target:self action:@selector(pageSnapshot)];
    page.enabled=running&&!building; self.navigationItem.leftBarButtonItem=page;
    ((UITextView *)self.view).text=pageStatus ?: finishedReport ?: (running?@"采集中：标记场景，操作后手动快照或停止；快照生成后可预览并手动存到文件。仅六个已有挂点。":@"类名、方法名和编码可能敏感。开始后标记场景，手动快照并选择存储到文件；未手动保存时进程退出会丢失。仅观察六个已有挂点，不自动上传。 ");
    UIBarButtonItem *toggle=[[UIBarButtonItem alloc] initWithTitle:running?@"停止":@"开始" style:UIBarButtonItemStylePlain target:self action:@selector(toggle)];
    UIBarButtonItem *mark=[[UIBarButtonItem alloc] initWithTitle:@"场景" style:UIBarButtonItemStylePlain target:self action:@selector(mark)];
    UIBarButtonItem *snap=[[UIBarButtonItem alloc] initWithTitle:@"快照" style:UIBarButtonItemStylePlain target:self action:@selector(snapshot)];
    UIBarButtonItem *share=[[UIBarButtonItem alloc] initWithTitle:@"保存/分享" style:UIBarButtonItemStylePlain target:self action:@selector(share:)];
    toggle.enabled=!building; mark.enabled=running&&!building; snap.enabled=running&&!building; share.enabled=!building&&finishedReport!=nil;
    self.navigationItem.rightBarButtonItems=@[toggle,mark,snap,share];
}
- (void)viewDidLoad { [super viewDidLoad]; UITextView *t=[UITextView new]; t.editable=NO; t.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; self.view=t; [self refresh]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }
- (void)begin {
    pthread_mutex_lock(&captureLock); memset(&capture,0,sizeof(capture)); atomic_store(&contended,0); atomic_store(&active,true); pthread_mutex_unlock(&captureLock);
    finishedReport=nil; pageStatus=nil; pageReports=[NSMutableArray array]; pageReportLength=0; pageReportsDropped=0; [self refresh];
}
- (void)toggle {
    if(building) return;
    if(atomic_load(&active)) { [self makeReport:YES]; return; }
    if(!finishedReport) { [self begin]; return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"开始新会话？" message:@"将丢弃当前内存报告；请先预览并按需手动保存。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"丢弃并开始" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x){ [self begin]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)mark {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"标记接下来操作的场景" message:@"仅使用固定标签；标记不代表页面识别。" preferredStyle:UIAlertControllerStyleActionSheet];
    for(unsigned i=1;i<SCENE_COUNT;i++) {
        unsigned scene=i; [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithUTF8String:scenes[i]] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ pthread_mutex_lock(&captureLock); if(atomic_load(&active)) { capture.scene=scene; capture.scenes[scene].marks++; } pthread_mutex_unlock(&captureLock); }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems[1]; [self presentViewController:a animated:YES completion:nil];
}
- (void)pageSnapshot {
    if(building || !atomic_load(&active)) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"10秒后采集页面类和几何？" message:@"确认后请返回目标界面；10秒后采集前台可见窗口（包括 MMMenuWindow）。记录层级和类名，以及精确 UIKit 和指定微信类名白名单的 frame、bounds 和滚动视图边距；宿主子类 getter 可能重写、有副作用或异常，主线程采集可能卡顿；滚动视图仅记录 bounds.size，不直接记录滚动偏移；但坐标、尺寸及层级可间接暴露消息长度、数量、类型、界面状态或滚动位置，也不能保证类名不含敏感内容。不会主动读取文本、消息、URL、账号或控件值。每会话最多4份、合计262144字符，超限整份丢弃且保留旧快照；停止时与事件合并。仅在计时结束及每批执行时前台才继续；期间进入后台又返回不能保证目标仍在。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"允许并开始倒计时" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){
        building=YES; pageStatus=@"页面类快照倒计时10秒，请返回目标界面；采集后重新打开本页。"; [self refresh];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            WUPageSnapshot(^(NSString *report){
                building=NO;
                if(report && atomic_load(&active)) {
                    if(WUPageCanAppend(pageReports.count,pageReportLength,report.length)) {
                        [pageReports addObject:report]; pageReportLength+=report.length;
                    } else { pageReportsDropped++; }
                    pageStatus=nil; [self makeReport:NO];
                } else { pageStatus=@"页面类快照取消：应用不在前台、系统不支持或会话已停止；已收集数据保留。"; [self refresh]; }
            });
        });
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)snapshot { pageStatus=nil; [self makeReport:NO]; }
- (void)makeReport:(BOOL)stop {
    if(building || !atomic_load(&active)) return;
    CaptureSnapshot *copy=malloc(sizeof(*copy));
    if(!copy) { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"快照失败" message:@"内存不足，采集仍在运行。" preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; return; }
    pthread_mutex_lock(&captureLock); if(stop) atomic_store(&active,false); *copy=capture; copy->contended=atomic_load(&contended); pthread_mutex_unlock(&captureLock);
    building=YES; [self refresh];
    NSArray<NSString *> *pages=[pageReports copy]; NSUInteger dropped=pageReportsDropped;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSMutableString *report=[Report(copy,stop) mutableCopy]; free(copy);
        [report appendFormat:@"\n【本会话页面快照】%lu 份；超限整份丢弃 %lu；最多4份、合计262144字符。\n",(unsigned long)pages.count,(unsigned long)dropped];
        for(NSUInteger i=0;i<pages.count;i++) [report appendFormat:@"\n【页面快照 %lu】\n%@\n",(unsigned long)(i+1),pages[i]];
        NSString *combined=[report copy];
        dispatch_async(dispatch_get_main_queue(), ^{ finishedReport=combined; building=NO; [self refresh]; });
    });
}
- (void)share:(UIBarButtonItem *)sender {
    if(building||!finishedReport) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"保存或分享已预览报告？" message:@"真实类名、方法名、编码、模块名及页面层级、坐标和尺寸可能敏感；几何可能间接暴露消息长度、数量、类型、界面状态或滚动位置。请先检查；选择“存储到文件”可手动保存，选择其他目的地可能发送。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"选择保存或分享方式" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        NSString *filename=[NSString stringWithFormat:@"WUCapture-%@.txt",NSUUID.UUID.UUIDString];
        NSURL *url=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
        NSError *error=nil; NSData *data=[finishedReport dataUsingEncoding:NSUTF8StringEncoding];
        if(!data || ![data writeToURL:url options:NSDataWritingAtomic|NSDataWritingFileProtectionComplete error:&error]) {
            UIAlertController *failure=[UIAlertController alertControllerWithTitle:@"无法创建报告文件" message:@"未保存；请检查设备空间和解锁状态后重试。" preferredStyle:UIAlertControllerStyleAlert]; [failure addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:failure animated:YES completion:nil]; return;
        }
        UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        sheet.completionWithItemsHandler=^(__unused UIActivityType type, __unused BOOL completed, __unused NSArray *items, __unused NSError *activityError){ [[NSFileManager defaultManager] removeItemAtURL:url error:nil]; };
        sheet.popoverPresentationController.barButtonItem=sender; [self presentViewController:sheet animated:YES completion:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
void WUShowCapture(UIViewController *owner) { [owner.navigationController pushViewController:[WUCaptureController new] animated:YES]; }
