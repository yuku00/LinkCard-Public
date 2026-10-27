// Compile this translation unit with -fno-objc-arc. The rest of the tweak may use ARC.
#import "LifecycleTrace.h"
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>
#import <mach/mach_time.h>
#import <sys/sysctl.h>
#include <string.h>
#include <stdbool.h>
#if __has_feature(objc_arc)
#error LifecycleTrace.m requires -fno-objc-arc (init self/nil/replacement +1 must pass through unchanged)
#endif
#define ECAP 8192
#define OCAP 2048
#define HCAP 160
// No observed object is retained, weak-registered, messaged, or described by this recorder.
typedef struct { uintptr_t ptr; Class cls; unsigned serial; BOOL retired; } Obj;
typedef struct { unsigned call,hook,thread,depth,refs[5]; BOOL exit; } Event;
typedef struct { const char *cls,*sel,*abi; const char *state,*actual; BOOL sampled; IMP original; atomic_uint hits; } Hook;
static Obj objects[OCAP]; static Event events[ECAP]; static Hook hooks[HCAP];
static unsigned onum,enum_,hnum,callnum,tnum; static BOOL objectLimit,eventLimit;
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static atomic_bool enabled; static uint64_t startTicks; static double secondsPerTick;
static _Thread_local unsigned threadID,depth;
static unsigned refLocked(id o) {
    if(!o) return 0;
    uintptr_t p=(uintptr_t)o; Class c=object_getClass(o);
    for(unsigned i=0;i<onum;i++) if(!objects[i].retired && objects[i].ptr==p && objects[i].cls==c) return objects[i].serial;
    if(onum==OCAP) { objectLimit=YES; return OCAP+1; }
    unsigned n=++onum; objects[n-1]=(Obj){p,c,n,NO}; return n;
}
static unsigned record(unsigned h,unsigned call,BOOL exit,id self,id a,id b,id c,id result) {
    if(!atomic_load_explicit(&enabled,memory_order_relaxed)) return 0;
    if((mach_absolute_time()-startTicks)*secondsPerTick>180.0) { atomic_store(&enabled,false); return 0; }
    pthread_mutex_lock(&lock);
    if(!atomic_load_explicit(&enabled,memory_order_relaxed)) { pthread_mutex_unlock(&lock); return 0; }
    if(enum_==ECAP) { eventLimit=YES; atomic_store(&enabled,false); pthread_mutex_unlock(&lock); return 0; }
    if(!threadID) threadID=++tnum;
    if(!exit) call=++callnum;
    Event *e=&events[enum_++]; *e=(Event){.call=call,.hook=h,.thread=threadID,.depth=depth,.exit=exit};
    e->refs[0]=refLocked(self); e->refs[1]=refLocked(a); e->refs[2]=refLocked(b); e->refs[3]=refLocked(c); e->refs[4]=refLocked(result);
    pthread_mutex_unlock(&lock); return call;
}
static void (*eventObserver)(id, const char *);
void FPLifecycleSetEventObserver(void (*observer)(id, const char *)) { if([NSThread isMainThread]) eventObserver=observer; }
static unsigned enter(unsigned h,id s,id a,id b,id c) {
    if([NSThread isMainThread] && eventObserver && (!strcmp(hooks[h].sel,"collectionView:didSelectItemAtIndexPath:") || !strcmp(hooks[h].sel,"fullDocumentManagerViewController:didUpdateHierarchy:displayedRootLocation:"))) eventObserver(s,hooks[h].sel);
    if(!atomic_load_explicit(&enabled,memory_order_relaxed)) return 0;
    unsigned hit=atomic_fetch_add_explicit(&hooks[h].hits,1,memory_order_relaxed)+1;
    // First 16 calls per natural getter; critical init/binding/subscription/dealloc are never sampled.
    if(hooks[h].sampled && hit>16) return 0;
    unsigned n=record(h,0,NO,s,a,b,c,nil); if(n) depth++; return n;
}
// Initializer entry may destroy/replace self: never inspect that pointer after the call.
static void leave(unsigned h,unsigned n,id result) { if(n) { if(depth) depth--; record(h,n,YES,nil,nil,nil,nil,result); } }
static void retire(id s) {
    pthread_mutex_lock(&lock);
    for(unsigned i=0;i<onum;i++) if(objects[i].ptr==(uintptr_t)s) objects[i].retired=YES;
    pthread_mutex_unlock(&lock);
}
static BOOL matches(Method m,const char *abi) {
    NSMethodSignature *a=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    NSMethodSignature *b=[NSMethodSignature signatureWithObjCTypes:abi];
    if(!a||!b||strcmp(a.methodReturnType,b.methodReturnType)||a.numberOfArguments!=b.numberOfArguments) return NO;
    for(NSUInteger i=0;i<a.numberOfArguments;i++) if(strcmp([a getArgumentTypeAtIndex:i],[b getArgumentTypeAtIndex:i])) return NO;
    return YES;
}
// No Swift entrypoint casting: only runtime-exposed Objective-C methods with checked ABI.
static void hook(const char *cn,const char *sn,const char *abi) {
    if(hnum==HCAP) return;
    unsigned h=hnum++; Hook *r=&hooks[h]; r->cls=cn; r->sel=sn; r->abi=abi; r->actual="-"; r->state="NOT_LOADED";
    r->sampled=!strcmp(abi,"@@:") && strcmp(sn,"init");
    Class cls=objc_getClass(cn); if(!cls) return;
    SEL sel=sel_registerName(sn); Method m=class_getInstanceMethod(cls,sel);
    if(!m) { r->state="MISSING_SELECTOR"; return; }
    r->actual=method_getTypeEncoding(m);
    // Do not accidentally replace NSObject/UIKit or instrument a parent and child twice.
    unsigned count=0; Method *own=class_copyMethodList(cls,&count); BOOL direct=NO;
    for(unsigned i=0;i<count;i++) if(method_getName(own[i])==sel) direct=YES; free(own);
    if(!direct) { r->state="SKIPPED_INHERITED"; return; }
    if(!matches(m,abi)) { r->state="SKIPPED_ABI"; return; }
    IMP orig=method_getImplementation(m), imp=NULL; r->original=orig;
    // MRC blocks pass through the original ownership convention: no retain/autorelease of self or return.
    if(!strcmp(abi,"@@:")) imp=imp_implementationWithBlock(^id(id s){ unsigned n=enter(h,s,nil,nil,nil); id v=((id(*)(id,SEL))orig)(s,sel); leave(h,n,v); return v; });
    else if(!strcmp(abi,"@@:@")) imp=imp_implementationWithBlock(^id(id s,id a){ unsigned n=enter(h,s,a,nil,nil); id v=((id(*)(id,SEL,id))orig)(s,sel,a); leave(h,n,v); return v; });
    else if(!strcmp(abi,"@@:@@")) imp=imp_implementationWithBlock(^id(id s,id a,id b){ unsigned n=enter(h,s,a,b,nil); id v=((id(*)(id,SEL,id,id))orig)(s,sel,a,b); leave(h,n,v); return v; });
    else if(!strcmp(abi,"@@:@@@")) imp=imp_implementationWithBlock(^id(id s,id a,id b,id c){ unsigned n=enter(h,s,a,b,c); id v=((id(*)(id,SEL,id,id,id))orig)(s,sel,a,b,c); leave(h,n,v); return v; });
    else if(!strcmp(abi,"@@:@@?")) imp=imp_implementationWithBlock(^id(id s,id a,id b){ unsigned n=enter(h,s,a,nil,nil); id v=((id(*)(id,SEL,id,id))orig)(s,sel,a,b); leave(h,n,v); return v; });
    else if(!strcmp(abi,"@@:Q@")) imp=imp_implementationWithBlock(^id(id s,unsigned long long a,id b){ unsigned n=enter(h,s,nil,nil,nil); id v=((id(*)(id,SEL,unsigned long long,id))orig)(s,sel,a,b); leave(h,n,v); return v; });
    else if(!strcmp(abi,"@@:@@Q")) imp=imp_implementationWithBlock(^id(id s,id a,id b,unsigned long long c){ unsigned n=enter(h,s,a,b,nil); id v=((id(*)(id,SEL,id,id,unsigned long long))orig)(s,sel,a,b,c); leave(h,n,v); return v; });
    else if(!strcmp(abi,"v@:")) imp=imp_implementationWithBlock(^(id s){ unsigned n=enter(h,s,nil,nil,nil); if(n && !strcmp(sn,"dealloc")) retire(s); ((void(*)(id,SEL))orig)(s,sel); leave(h,n,nil); });
    else if(!strcmp(abi,"v@:@")) imp=imp_implementationWithBlock(^(id s,id a){ unsigned n=enter(h,s,a,nil,nil); ((void(*)(id,SEL,id))orig)(s,sel,a); leave(h,n,nil); });
    else if(!strcmp(abi,"v@:@@")) imp=imp_implementationWithBlock(^(id s,id a,id b){ unsigned n=enter(h,s,a,b,nil); ((void(*)(id,SEL,id,id))orig)(s,sel,a,b); leave(h,n,nil); });
    else if(!strcmp(abi,"v@:@@@")) imp=imp_implementationWithBlock(^(id s,id a,id b,id c){ unsigned n=enter(h,s,a,b,c); ((void(*)(id,SEL,id,id,id))orig)(s,sel,a,b,c); leave(h,n,nil); });
    else if(!strcmp(abi,"v@:BB")) imp=imp_implementationWithBlock(^(id s,BOOL a,BOOL b){ unsigned n=enter(h,s,nil,nil,nil); ((void(*)(id,SEL,BOOL,BOOL))orig)(s,sel,a,b); leave(h,n,nil); });
    if(!imp) { r->state="SKIPPED_UNSUPPORTED_ABI"; return; }
    method_setImplementation(m,imp); r->state="INSTALLED";
}

void FPLifecycleStart(void) {
    static BOOL started; if(started) return; started=YES;
    if(![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.DocumentsApp"]) return;
    char build[64]={0}; size_t size=sizeof(build); sysctlbyname("kern.osversion",build,&size,NULL,0);
    if(strcmp(build,"20G75")) return;
    mach_timebase_info_data_t tb; mach_timebase_info(&tb); secondsPerTick=(double)tb.numer/tb.denom/1e9;
    startTicks=mach_absolute_time();
    const char *managers[]={"DOCFullDocumentManagerViewController","DOCSplitBrowserViewController","Files.DOCBrowserNavigationDataSource","Files.DOCSidebarViewController"};
    for(unsigned i=0;i<4;i++) hook(managers[i],"initWithConfiguration:sourceObserver:","@@:@@");
    hook("DOCTabbedBrowserViewController","initWithConfiguration:","@@:@");
    hook("Files.DRIMainViewController","initWithConfiguration:","@@:@");
    hook("Files.DOCDocumentManager","initWithConfiguration:sourceObserver:hierarchyController:","@@:@@@");
    hook("Files.DOCHierarchyController","initWithConfiguration:sourceObserver:minParentLocations:","@@:@@Q");
    hook("DOCSourceObserver","initWithUserAction:hostIdentifier:","@@:Q@");
    hook("DOCSourceObserver","addSubscriberForConfiguration:usingBlock:","@@:@@?");
    hook("DOCSourceObserver","_addSubscriberForConfiguration:usingBlock:","@@:@@?");
    hook("DOCSourceObserver","removeSubscriberForToken:","v@:@");
    hook("DOCSourceObserver","startObservingSources","v@:");
    hook("DOCSourceObserver","stopObservingSources","v@:");
    hook("DOCConfiguration","updateStateAndSceneIdentifiersWithWindow:","v@:@");
    hook("Files.WindowSceneDelegate","scene:willConnectToSession:options:","v@:@@@");
    hook("Files.WindowSceneDelegate","sceneDidDisconnect:","v@:@");
    hook("Files.WindowSceneDelegate","setWindow:","v@:@");
    hook("Files.DOCDocumentManager","setDocumentBrowser:","v@:@");
    hook("Files.DOCDocumentManager","setUiBrowserDelegate:","v@:@");
    hook("Files.DOCHierarchyController","setDelegate:","v@:@");
    hook("Files.DOCBrowserNavigationDataSource","setItemProvider:","v@:@");
    hook("Files.DOCBrowserNavigationDataSource","setUpdateObserver:","v@:@");
    hook("DOCFullDocumentManagerViewController","setDelegate:","v@:@");
    hook("DOCFullDocumentManagerViewController","setHierarchyController:","v@:@");
    hook("DOCFullDocumentManagerViewController","setActionManager:","v@:@");
    hook("DOCFullDocumentManagerViewController","setDocumentManager:","v@:@");
    hook("DOCFullDocumentManagerViewController","setSourceObserver:","v@:@");
    hook("DOCTabbedBrowserViewController","setSourceObserver:","v@:@");
    // Natural reads only: these hooks never cause a getter to run.
    const char *getters[]={"configuration","sourceObserver","hierarchyController","actionManager","documentManager","dataSource","internalNavigationController"};
    for(unsigned i=0;i<sizeof(getters)/sizeof(getters[0]);i++) hook("DOCFullDocumentManagerViewController",getters[i],"@@:");
    hook("DOCTabbedBrowserViewController","sourceObserver","@@:");
    hook("Files.DRIMainViewController","configuration","@@:");
    hook("Files.DOCBrowserContainerController","dataSource","@@:");
    hook("Files.DOCItemCollectionViewController","actionReporting","@@:");
    hook("Files.DOCItemCollectionViewController","setActionReporting:","v@:@");
    hook("Files.DOCItemCollectionViewController","collectionView:didSelectItemAtIndexPath:","v@:@@");
    hook("Files.DOCItemCollectionViewController","collectionView:didDeselectItemAtIndexPath:","v@:@@");
    hook("Files.DOCItemCollectionViewController","setEditing:animated:","v@:BB");
    hook("Files.DOCBrowserContainerController","setEditing:animated:","v@:BB");
    hook("DOCSplitBrowserViewController","fullDocumentManagerViewController:didUpdateHierarchy:displayedRootLocation:","v@:@@@");
    hook("Files.DOCBrowserHistoryDataSource","init","@@:");
    hook("Files.DOCActionManager","init","@@:");
    const char *lives[]={"DOCFullDocumentManagerViewController","DOCSplitBrowserViewController","DOCTabbedBrowserViewController","DOCSourceObserver","DOCSourceObserverToken","Files.DOCDocumentManager","Files.DOCHierarchyController","Files.DOCBrowserHistoryDataSource","Files.DOCBrowserNavigationDataSource","Files.DOCBrowserContainerController","Files.DOCItemCollectionViewController"};
    for(unsigned i=0;i<sizeof(lives)/sizeof(lives[0]);i++) hook(lives[i],"dealloc","v@:");
    atomic_store(&enabled,true);
}
void FPLifecycleStop(void) { atomic_store(&enabled,false); }
static void protocolInfo(Protocol *p,NSMutableSet *seen,NSMutableString *out) {
    NSString *name=@(protocol_getName(p)); if([seen containsObject:name]) return; [seen addObject:name];
    [out appendFormat:@"PROTOCOL %@\n",name];
    for(int req=0;req<2;req++) for(int inst=0;inst<2;inst++) {
        unsigned n=0; struct objc_method_description *ds=protocol_copyMethodDescriptionList(p,req,inst,&n);
        for(unsigned i=0;i<n;i++) [out appendFormat:@" P required=%d instance=%d %s %s\n",req,inst,sel_getName(ds[i].name),ds[i].types?:"?"]; free(ds);
    }
    unsigned n=0; Protocol *__unsafe_unretained *parents=protocol_copyProtocolList(p,&n);
    for(unsigned i=0;i<n;i++) protocolInfo(parents[i],seen,out); free(parents);
}
NSString *FPLifecycleReport(void) {
    FPLifecycleStop();
    NSMutableString *out=[NSMutableString stringWithString:@"Files lifecycle trace 0.3.0; final native experiment round\nObject IDs are process-local address/class observations. A dealloc retires tracked IDs; pointer reuse without a tracked dealloc is ambiguous. No proof of retention ownership follows from IDs alone.\nINIT return self/nil/replacement is passed through with original MRC ownership. Only Objective-C dispatch is observed; direct Swift calls are not. See experiment section for new-instance construction/presentation. No completion block was wrapped or invoked by this recorder. The recorder performs no file/prefs operations; normal Files history writes remain allowed.\nNatural getters record their first 16 calls per selector/class; hits counts all calls until stop/deadline. Critical lifecycle events are not sampled. Event order is lock acquisition order, with per-thread nesting; not a cross-thread causal proof.\nStop freezes capture; installed hooks remain transparent pass-through until process exit. No re-arm, disk log, or upload.\n"];
    pthread_mutex_lock(&lock);
    [out appendFormat:@"EVENTS %u/%d OBJECTS %u/%d eventCap=%d objectCap=%d elapsed=%.1fs deadline=180s\n",enum_,ECAP,onum,OCAP,eventLimit,objectLimit,(mach_absolute_time()-startTicks)*secondsPerTick];
    for(unsigned i=0;i<hnum;i++) {
        Hook *r=&hooks[i]; unsigned hits=atomic_load(&r->hits);
        [out appendFormat:@"HOOK h%u %s %s expected=%s actual=%s status=%s hits=%u sampledGetter=%d %s\n",i,r->cls,r->sel,r->abi,r->actual,r->state,hits,r->sampled,!strcmp(r->state,"INSTALLED")?(hits?"HIT":"UNHIT"):"NOT_HOOKED"];
    }
    for(unsigned i=0;i<onum;i++) [out appendFormat:@"OBJECT o%u %s retired=%d\n",objects[i].serial,class_getName(objects[i].cls),objects[i].retired];
    for(unsigned i=0;i<enum_;i++) {
        Event e=events[i]; [out appendFormat:@"%u call=%u t=%u depth=%u h%u %s self=o%u args=o%u,o%u,o%u return=o%u\n",i+1,e.call,e.thread,e.depth,e.hook,e.exit?"EXIT":"ENTER",e.refs[0],e.refs[1],e.refs[2],e.refs[3],e.refs[4]];
    }
    pthread_mutex_unlock(&lock);
    [out appendString:@"o0=nil/unrecorded; o2049=OBJECT_LIMIT. Block args, userAction enum values and hostIdentifier are deliberately not recorded.\nTARGETED_CONTRACT_METADATA (no ivar values)\n"];
    NSMutableSet *classes=[NSMutableSet set],*protocols=[NSMutableSet set];
    for(unsigned i=0;i<hnum;i++) {
        Class c=objc_getClass(hooks[i].cls);
        while(c) {
            NSString *name=@(class_getName(c)); if([classes containsObject:name]) break; [classes addObject:name];
            [out appendFormat:@"CLASS %@ SUPER %s\n",name,class_getSuperclass(c)?class_getName(class_getSuperclass(c)):"nil"];
            // Stop at UIKit/Foundation: names are enough; no framework-wide metadata dump.
            if([name hasPrefix:@"UI"]||[name hasPrefix:@"NS"]) break;
            unsigned count=0; objc_property_t *props=class_copyPropertyList(c,&count);
            for(unsigned j=0;j<count;j++) [out appendFormat:@" PROPERTY %s %s\n",property_getName(props[j]),property_getAttributes(props[j])]; free(props);
            Protocol *__unsafe_unretained *ps=class_copyProtocolList(c,&count);
            for(unsigned j=0;j<count;j++) protocolInfo(ps[j],protocols,out); free(ps);
            // Only the hook selectors and lifecycle-relevant methods: not every method in Files.
            Method *ms=class_copyMethodList(c,&count);
            for(unsigned j=0;j<count;j++) {
                const char *s=sel_getName(method_getName(ms[j]));
                if(strstr(s,"init")||strstr(s,"dealloc")||strstr(s,"cancel")||strstr(s,"invalidate")||strstr(s,"Pending")||strstr(s,"ubscri")||strstr(s,"History")||strstr(s,"history")||strstr(s,"delegate")||strstr(s,"Delegate")||strstr(s,"ctionReporting")||strstr(s,"etScene")) [out appendFormat:@" METHOD %s %s\n",s,method_getTypeEncoding(ms[j])];
            } free(ms); c=class_getSuperclass(c);
        }
    }
    return out;
}
