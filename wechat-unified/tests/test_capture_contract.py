from pathlib import Path
import subprocess, tempfile, unittest
R=Path(__file__).resolve().parents[1]
S=(R/'Sources/WUCapture.m').read_text()

class CaptureContract(unittest.TestCase):
    def test_callback_and_metadata(self):
        cb=S.split('void WUCaptureObserve',1)[1].split('static NSString *RuntimeString',1)[0]
        for v in ('pthread_mutex_trylock','object_getClass(object)','class_getName','memcpy','s->windowCount>=20','s->count>=SCENE_LIMIT'):
            self.assertIn(v,cb)
        for v in ('class_copyMethodList','pthread_mutex_lock','objc_msgSend'):
            self.assertNotIn(v,cb)
        event=S.split('typedef struct { char name',1)[1].split('CaptureEvent;',1)[0]
        self.assertNotIn('Class ',event)
        for v in ('objc_lookUpClass(name.UTF8String)','class_copyMethodList','method_getTypeEncoding','depth<8','unique.count<24','UIActivityViewController','NSDataWritingFileProtectionComplete','removeItemAtURL','dispatch_get_global_queue'):
            self.assertIn(v,S)
        for v in ('class_getInstanceVariable','valueForKey:', 'NSURLSession', 'UIPasteboard', 'NSLog(', 'WUHook('):
            self.assertNotIn(v,S)
    def test_wiring_and_offline_packaging(self):
        self.assertIn('WUShowCapture(self)',(R/'Sources/WUDiagnostics.m').read_text())
        surface=(R/'Sources/Surfaces.m').read_text()
        for v in ('WUCaptureObserve(v,3)','WUCaptureObserve(tool,2)'): self.assertIn(v,surface)
        self.assertIn('WUCaptureObserve(v,1)',(R/'Sources/Messages.m').read_text())
        voice=(R/'Sources/Voice.m').read_text().split('static void SetPlaying(',1)[1].split('static ',1)[0]
        self.assertIn('playingOriginal)(vm,cmd,value); WUCaptureObserve(vm,4);',voice)
        pat=(R/'Sources/WUNativeInteractions.m').read_text().split('static void Pat(',1)[1].split('static ',1)[0]
        self.assertLess(pat.index('WUCaptureObserve(cell,5)'),pat.index('WUNativeEnabled('))
        mini=(R/'Sources/WUMiniAds.m').read_text().split('static id Invoke(',1)[1].split('void WUInstallMiniAds(',1)[0]
        self.assertIn('WUCaptureObserve(object,6)',mini)
        self.assertEqual(mini.count('opaqueArgument'),2)
        self.assertNotIn('@catch',mini)
        release=(R/'tools/release.py').read_text()
        for f in ('Sources/WUCapture.m','Sources/WUCapture.h','CAPTURE-GUIDE.md','tests/test_capture_contract.py'): self.assertIn(f,release)
    def test_page_snapshot_contract(self):
        page=S.split('static void WUPageSnapshot',1)[1].split('static NSString *pageStatus',1)[0]
        for token in ('connectedScenes','UISceneActivationStateForegroundActive','ws.windows','w.windowScene!=ws','w.hidden','w.alpha','w.rootViewController','childViewControllers','presentedViewController','subviews','queue.count>=1024','index+32','scannedWindows++>=64','windowCount>=32','sceneCount>=16','dispatch_get_main_queue()','UIApplicationStateActive'):
            self.assertIn(token,page)
        for forbidden in ('valueForKey','performSelector','objc_msgSend','text','URL','NSUserDefaults','UIPasteboard','NSLog','class_copyMethodList'):
            self.assertNotIn(forbidden,page)
        for token in ('允许并开始倒计时','10*NSEC_PER_SEC','MMMenuWindow','finishedReport=combined','UIActivityViewController'):
            self.assertIn(token,S)
    def test_page_merge_and_geometry_contract(self):
        page=S.split('static void WUPageSnapshot',1)[1].split('static NSString *pageStatus',1)[0]
        self.assertIn('if(!n.controller) WUPageAppendGeometry(out,obj)',page)
        geometry=(R/'Sources/WUPageGeometry.inc').read_text()
        for token in ('type==UIView.class','type==UIScrollView.class','type==UITableView.class','type==UICollectionView.class','view.frame','view.bounds','b.size.width','s.contentInset','s.adjustedContentInset','isKindOfClass:UIView.class','isKindOfClass:UIScrollView.class','@catch','isfinite','截断'):
            self.assertIn(token,geometry)
        for token in ('MMTableView','NSKVONotifying_MMTableView','MMInputToolView','InputToolContainerView','InputToolViewBar','EmoticonMessageCellView','AppEmoticonMessageCellView'):
            self.assertIn('"'+token+'"',geometry)
        for token in ('contentOffset','valueForKey','performSelector','objc_msgSend','text','NSUserDefaults','UIPasteboard','NSURLSession'):
            self.assertNotIn(token,geometry)
        self.assertLess(geometry.index('if(scroll) [out appendFormat:'),geometry.index('else [out appendFormat:'))
        controller=S.split('- (void)pageSnapshot',1)[1].split('- (void)share:',1)[0]
        for token in ('WUPageCanAppend(pageReports.count,pageReportLength,report.length)','[pageReports addObject:report]','pageReportsDropped++','[pageReports copy]','Report(copy,stop)','pages[i]','finishedReport=combined'):
            self.assertIn(token,controller)
        self.assertNotIn('finishedReport=report',controller)
    def test_geometry_privacy_and_package_contract(self):
        release=(R/'tools/release.py').read_text()
        for path in ('Sources/WUPageGeometry.inc','tests/page_geometry_ios.m','tools/test_page_geometry_ios.py'):
            self.assertIn(path,release)
        self.assertIn('#import "WUPageGeometry.inc"',S)
        self.assertIn('Sources/*.m',(R/'tools/build.sh').read_text())
        for section in (S.split('static void WUPageSnapshot',1)[1].split('NSMutableArray<WUPageNode',1)[0], S.split('- (void)pageSnapshot',1)[1].split('[a addAction:',1)[0], S.split('- (void)share:',1)[1].split('[a addAction:',1)[0]):
            self.assertIn('间接',section)
            self.assertIn('滚动位置',section)
        self.assertIn('不等于无法推断滚动位置',(R/'CAPTURE-GUIDE.md').read_text())
    def test_actual_page_budget(self):
        start=S.index('#define PAGE_REPORT_COUNT_LIMIT')
        end=S.index('static NSString *finishedReport;',start)
        budget=S[start:end]
        program='''#include <stddef.h>
#include <stdbool.h>
#include <assert.h>
'''+budget+'''
int main(void) {
 assert(WUPageCanAppend(0,0,262144));
 assert(!WUPageCanAppend(0,0,262145));
 assert(WUPageCanAppend(3,262143,1));
 assert(!WUPageCanAppend(4,0,1));
 assert(!WUPageCanAppend(1,262144,1));
 assert(!WUPageCanAppend(1,262145,0));
 return 0;
}
'''
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'budget.c'; p.write_text(program)
            subprocess.run(['cc','-std=c11',str(p),'-o',str(Path(d)/'budget')],check=True)
            subprocess.run([str(Path(d)/'budget')],check=True)
    def test_page_budget_mock(self):
        # Model the same per-batch queue admission and report limits, not UIKit behavior.
        queue=[('root',0)]; index=0; truncated=False; batches=[]
        while index<len(queue):
            end=min(index+32,len(queue)); batches.append(end-index)
            while index<end:
                name,depth=queue[index]; index+=1
                if depth<4:
                    for i in range(16):
                        if len(queue)>=1024:
                            truncated=True; break
                        queue.append((str(i),depth+1))
        self.assertEqual(index,1024)
        self.assertTrue(truncated)
        self.assertLessEqual(max(batches),32)
    def test_actual_callback_with_runtime_stubs(self):
        defs=S[S.index('#define SCENE_COUNT'):S.index('static BOOL building;')]
        callback='void WUCaptureObserve'+S.split('void WUCaptureObserve',1)[1].split('static NSString *RuntimeString',1)[0]
        program='''#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#include <time.h>
#include <assert.h>
static int fake_clock(clockid_t clock, struct timespec *ts){ (void)clock; ts->tv_sec=100; ts->tv_nsec=0; return 0; }
#define clock_gettime fake_clock
typedef char *id;
static id object_getClass(id o){return o;}
static const char *class_getName(id c){return c;}
'''+defs+callback+'''
int main(void){
 char name[16]="First"; atomic_store(&active,true);
 for(int i=0;i<21;i++) WUCaptureObserve(name,1);
 assert(capture.scenes[0].count==20 && capture.scenes[0].limited==1);
 strcpy(name,"Changed"); assert(!strcmp(capture.scenes[0].events[0].name,"First"));
 capture.scene=1; WUCaptureObserve(name,2); assert(capture.scenes[1].count==1);
 capture.scenes[1].count=SCENE_LIMIT; capture.scenes[1].windowCount=0;
 WUCaptureObserve(name,2); assert(capture.scenes[1].full==1);
 capture.scene=2; WUCaptureObserve(name,3); assert(capture.scenes[2].count==1);
 for(unsigned point=4;point<=6;point++) {
  capture.scene=point; WUCaptureObserve(name,point);
  assert(capture.scenes[point].count==1 && capture.scenes[point].events[0].point==point);
  assert(!strcmp(capture.scenes[point].events[0].name,"Changed"));
  for(int i=0;i<20;i++) WUCaptureObserve(name,point);
  assert(capture.scenes[point].count==20 && capture.scenes[point].limited==1);
 }
 WUCaptureObserve(name,0); WUCaptureObserve(name,7); assert(capture.scenes[6].count==20);
 capture.scene=2;
 pthread_mutex_lock(&captureLock); WUCaptureObserve(name,1); pthread_mutex_unlock(&captureLock);
 assert(atomic_load(&contended)==1);
 atomic_store(&active,false); WUCaptureObserve(name,1); assert(capture.scenes[2].count==1);
 return 0;
}
'''
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'test.c'; p.write_text(program)
            subprocess.run(['cc','-std=c11','-pthread',str(p),'-o',str(Path(d)/'test')],check=True)
            subprocess.run([str(Path(d)/'test')],check=True)
if __name__=='__main__': unittest.main()
