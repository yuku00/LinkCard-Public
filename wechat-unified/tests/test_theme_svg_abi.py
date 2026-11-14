import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'Sources/Themes.m').read_text()


class ThemeSVGABI(unittest.TestCase):
    def test_install_signatures_and_fallback(self):
        install = SOURCE.split('void WUInstallThemes(void) {', 1)[1].split('\n}', 1)[0]
        lines = [line.strip() for line in install.splitlines() if 'svgImageNamed:size:color:alpha:angle:ignoreNotFound:' in line]
        self.assertEqual(len(lines), 2)
        common = '@[@"@",[NSString stringWithUTF8String:@encode(CGSize)],@"@",[NSString stringWithUTF8String:@encode(CGFloat)],'
        tail = ',[NSString stringWithUTF8String:@encode(BOOL)]]'
        self.assertIn(common + '@"i"' + tail, lines[0])
        self.assertIn(common + '[NSString stringWithUTF8String:@encode(CGFloat)]' + tail, lines[1])
        self.assertTrue(lines[0].startswith('if(!WUHook('))
        self.assertIn('(IMP)SVGNamedInt,&svgIntIMP', lines[0])
        self.assertIn('(IMP)SVGNamedDouble,&svgDoubleIMP', lines[1])
        core = (ROOT / 'Sources/Core.m').read_text()
        self.assertIn('method_getNumberOfArguments(m)!=args.count+2', core)
        self.assertIn('if(!WUMatches(m,ret,args))', core)

    def test_arm64_compile_actual_hook_bodies(self):
        bodies = SOURCE.split('static UIImage *SVGNamedInt(', 1)[1].split('static UIImage *UINamed(', 1)[0]
        bodies = 'static UIImage *SVGNamedInt(' + bodies
        prelude = '''
typedef double CGFloat;
typedef struct { CGFloat width, height; } CGSize;
typedef signed char BOOL;
typedef unsigned long NSUInteger;
typedef struct objc_selector *SEL;
typedef void (*IMP)(void);
@interface NSString @end
@interface UIColor @end
@interface UIImage @end
@interface UITraitCollection
+ (UITraitCollection *)currentTraitCollection;
@end
static IMP svgIntIMP,svgDoubleIMP;
static _Thread_local NSUInteger resourceDepth;
static UIImage *Replacement(NSString *, UIImage *, UITraitCollection *, CGSize, UIColor *);
'''
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / 'abi.m'
            path.write_text(prelude + bodies)
            result = subprocess.run(['clang', '-target', 'arm64-apple-ios13.0', '-fsyntax-only', '-fobjc-arc', '-Werror', '-Wno-undefined-internal', str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        for name, ctype, imp in [('Int', 'int', 'svgIntIMP'), ('Double', 'CGFloat', 'svgDoubleIMP')]:
            body = re.search(r'static UIImage \*SVGNamed' + name + r'\((.*?)\n}', bodies, re.S).group(1)
            self.assertIn('CGFloat alpha,' + ctype + ' angle,BOOL ignore', body)
            self.assertIn('CGFloat,' + ctype + ',BOOL))' + imp + ')(o,s,n,size,color,alpha,angle,ignore)', body)
            self.assertIn('if(!outer||alpha!=1||angle!=0) return original;', body)
            self.assertIn('?:original', body)
            self.assertIn('@finally { resourceDepth--; }', body)


if __name__ == '__main__':
    unittest.main()
