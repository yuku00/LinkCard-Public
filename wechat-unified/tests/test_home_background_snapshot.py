import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'Sources/HomeGroups.m').read_text()


def body(start):
    pos = SOURCE.index(start)
    brace = SOURCE.index('{', pos)
    level = 1
    end = brace + 1
    while level:
        level += (SOURCE[end] == '{') - (SOURCE[end] == '}')
        end += 1
    return SOURCE[pos:end]


class HomeBackgroundSnapshotTests(unittest.TestCase):
    def test_projection_gate_and_original_calls_are_unlocked(self):
        safe = body('static BOOL WUHomeProjectionSafe(')
        apply = body('- (void)apply {')
        capture = body('static void Capture(id m,')
        self.assertEqual(safe, 'static BOOL WUHomeProjectionSafe(void) { return NO; }')
        prefix = apply.split('if(applying', 1)[0]
        self.assertIn('if(!WUHomeProjectionSafe()) return;', prefix)
        self.assertNotIn('setters[', prefix)
        self.assertNotIn('SetCount(', prefix)
        for name in ('static WUHomeSnapshot *Snapshot(', 'static void Capture(id m,',
                     'static void CountSigned(', 'static void CountUnsigned(', '- (void)apply {'):
            text = body(name)
            self.assertNotIn('@synchronized', text)
            self.assertNotIn('dispatch_sync', text)
        self.assertIn('if(applying || !NSThread.isMainThread)', capture)
        self.assertIn('sw.enabled=ready && WUHomeProjectionSafe()', SOURCE)
        self.assertIn('原会话列表及已保存的分组配置均保留', SOURCE)

    def test_compiled_gate_and_background_setter_interleavings(self):
        # Compile the actual guard and off-main Capture passthrough as C. The
        # rest of Capture is not exercised; its Objective-C runtime is absent.
        safe = body('static BOOL WUHomeProjectionSafe(')
        apply = body('- (void)apply {')
        guard = apply.split('if(applying', 1)[0].replace('- (void)apply', 'static void apply(void)')
        capture = body('static void Capture(id m,')
        capture_prefix = capture.split('    WUHomeSnapshot *s=Snapshot(m);', 1)[0]
        capture_prefix = capture_prefix.replace('NSUInteger', 'size_t').replace('!NSThread.isMainThread', '!isMainThread')
        program = r'''
#include <assert.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>
typedef void *id; typedef void *SEL; typedef int BOOL; typedef void (*IMP)(void);
#define NO 0
static IMP setters[3];
static BOOL applying;
static _Thread_local BOOL isMainThread;
static int host_value, snapshot_value=1, projected_writes;
static pthread_t worker_id, called_id;
static pthread_mutex_t mu=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond=PTHREAD_COND_INITIALIZER;
static int entered, release_original, wait_inside;
''' + safe + '\n' + guard + r'''
    host_value=snapshot_value; ++projected_writes;
}
''' + capture_prefix + r'''
    assert(0); /* main-thread part is outside this shim */
}
static void original(id m, SEL sel, id value) {
    (void)m; (void)sel;
    pthread_mutex_lock(&mu);
    called_id=pthread_self(); entered=1; pthread_cond_broadcast(&cond);
    while(wait_inside && !release_original) pthread_cond_wait(&cond,&mu);
    host_value=(int)(intptr_t)value;
    pthread_mutex_unlock(&mu);
}
static void *background(void *arg) {
    worker_id=pthread_self(); isMainThread=0;
    Capture((id)1,(SEL)2,arg,2); return NULL;
}
static void start(pthread_t *thread, int value, int wait) {
    pthread_mutex_lock(&mu); entered=0; release_original=0; wait_inside=wait; pthread_mutex_unlock(&mu);
    assert(!pthread_create(thread,NULL,background,(id)(intptr_t)value));
    pthread_mutex_lock(&mu);
    while(!entered) pthread_cond_wait(&cond,&mu);
    pthread_mutex_unlock(&mu);
}
static void finish(pthread_t thread) {
    pthread_mutex_lock(&mu); release_original=1; pthread_cond_broadcast(&cond); pthread_mutex_unlock(&mu);
    assert(!pthread_join(thread,NULL)); assert(pthread_equal(worker_id,called_id));
}
int main(void) {
    pthread_t thread; isMainThread=1; setters[2]=(IMP)original;
    /* Background setter completes before refresh and disabled fallback. */
    start(&thread,2,0); finish(thread); apply(); apply();
    assert(host_value==2 && projected_writes==0);
    /* Host setter waits for main: refresh must not wait on its manager lock. */
    start(&thread,3,1); apply(); finish(thread); apply();
    assert(host_value==3 && projected_writes==0);
    /* Host update occurs after refresh/disable, then another refresh. */
    apply(); start(&thread,4,0); finish(thread); apply();
    assert(host_value==4 && projected_writes==0);
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)
            (path / 'test.c').write_text(program)
            subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pthread',
                            str(path / 'test.c'), '-o', str(path / 'test')], check=True)
            subprocess.run([str(path / 'test')], check=True, timeout=10)


if __name__ == '__main__':
    unittest.main()
