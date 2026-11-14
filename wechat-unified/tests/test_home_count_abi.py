import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'Sources/HomeGroups.m').read_text()


def function(name):
    start = SOURCE.index('static void ' + name + '(')
    brace = SOURCE.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (SOURCE[end] == '{') - (SOURCE[end] == '}')
        end += 1
    return SOURCE[start:end]


class HomeCountTests(unittest.TestCase):
    def test_signature_and_restore_wiring(self):
        self.assertIn('WUMatches(countMethod,"v",@[@"q"])', SOURCE)
        self.assertIn('WUMatches(countMethod,"v",@[@"Q"])', SOURCE)
        self.assertIn('q?(IMP)CountSigned:(IMP)CountUnsigned', SOURCE)
        self.assertIn('self.countUsable &&', SOURCE)
        self.assertIn('q>=0 && (unsigned long long)q<=NSUIntegerMax', SOURCE)
        self.assertIn('u<=NSUIntegerMax', SOURCE)
        self.assertIn('SetCount(self.manager,NO,self.unsignedTopCount,self.signedTopCount)', SOURCE)
        self.assertIn('gen!=WUContextGeneration()', SOURCE)
        self.assertIn('self.manager==CurrentManager()', SOURCE)
        self.assertIn('snap.source=[NSMutableArray arrayWithArray:@[NSNull.null,NSNull.null,NSNull.null]]', SOURCE)

    def test_exact_typed_original_calls(self):
        # Compile the actual dispatch helper and passthrough callback bodies with
        # a tiny C shim; no Apple runtime or fake assertion about device behavior.
        parts = [function(n) for n in ('SetCount', 'CountSigned', 'CountUnsigned')]
        code = '\n'.join(parts).replace('NSSelectorFromString(@"setTotalTopSessionCount:")', '0')
        code = code.replace('!NSThread.isMainThread', '!isMainThread')
        harness = r'''
#include <assert.h>
#include <limits.h>
typedef void *id; typedef void *SEL; typedef void (*IMP)(void); typedef int BOOL;
static IMP countSetter; static BOOL countSigned, applying, isMainThread;
static long long seenQ; static unsigned long long seenU;
static void originalQ(id m, SEL s, long long n) { (void)m; (void)s; seenQ=n; }
static void originalU(id m, SEL s, unsigned long long n) { (void)m; (void)s; seenU=n; }
static void CaptureCount(id m, unsigned long long u, long long q) { (void)m; (void)u; (void)q; assert(0); }
''' + code + r'''
int main(void) {
 countSigned=1; countSetter=(IMP)originalQ;
 SetCount(0,0,0,LLONG_MIN); assert(seenQ==LLONG_MIN);
 SetCount(0,0,0,-1); assert(seenQ==-1);
 SetCount(0,0,0,LLONG_MAX); assert(seenQ==LLONG_MAX);
 SetCount(0,1,20000,-1); assert(seenQ==20000);
 CountSigned(0,0,LLONG_MIN); assert(seenQ==LLONG_MIN);
 countSigned=0; countSetter=(IMP)originalU;
 SetCount(0,0,ULLONG_MAX,0); assert(seenU==ULLONG_MAX);
 SetCount(0,1,20000,0); assert(seenU==20000);
 CountUnsigned(0,0,ULLONG_MAX); assert(seenU==ULLONG_MAX);
 return 0;
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            source = pathlib.Path(tmp) / 'count.c'
            binary = pathlib.Path(tmp) / 'count'
            source.write_text(harness)
            subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
