"""Contracts plus execution of the exact fixed JS in a synthetic DOM (not WebKit)."""
from pathlib import Path
import json, re, shutil, subprocess, unittest
ROOT=Path(__file__).resolve().parents[1]
UI=(ROOT/'Sources/WUArticleImage.m').read_text()
NET=(ROOT/'Sources/WUArticleImageFetch.m').read_text()
DOM=(ROOT/'Sources/WUArticleImageDOM.inc').read_text()
IMAGE=(ROOT/'Sources/WUImageEntry.m').read_text()

class ArticleContract(unittest.TestCase):
    def test_real_install_and_setting(self):
        core=(ROOT/'Sources/Core.m').read_text()
        settings=(ROOT/'Sources/Settings.m').read_text()
        self.assertIn('WUInstallArticleImage();',core)
        self.assertEqual(core.count('@"articleImage"'),2)
        self.assertIn('@[@"articleImage",',settings)
        self.assertIn('WUArticleImageAvailable()',settings)
        self.assertIn('WUHook(@"WKWebView",@"layoutSubviews"',UI)
        self.assertIn('-framework WebKit',(ROOT/'tools/build.sh').read_text())
        self.assertNotIn('WUChatSession',UI)
    def test_native_gesture_is_only_selector(self):
        pressed=UI[UI.index('- (void)pressed:'):UI.index('- (void)verify:(NSString *)mode completion:',UI.index('@implementation WUArticleImage'))]
        for part in ['press!=self.press || !press.nativeTouch','UIGestureRecognizerStateBegan','Now()-press.began<0.5','WUArticleURL(self.web.URL)','WUCurrentAccount()','WUContextGeneration()','NSUUID.UUID.UUIDString','self.deadline=Now()+12']:
            self.assertIn(part,pressed)
        self.assertEqual(UI.count('[self verify:@"select"'),1)
        self.assertNotIn('startURL:',pressed)
        for no in ['WKScriptMessage','addScriptMessageHandler','evaluateJavaScript','UIPasteboard','NSLog','getAllCookies','setNavigationDelegate','UIDocumentPicker','WUHook(@"UILabel"']:
            self.assertNotIn(no,UI)
    def test_original_menu_and_gestures_preserved(self):
        for part in ['canPreventGestureRecognizer:', 'canBePreventedByGestureRecognizer:', 'return NO;', 'press.cancelsTouchesInView=NO', 'press.delaysTouchesBegan=NO','press.delaysTouchesEnded=NO','shouldRecognizeSimultaneouslyWithGestureRecognizer:', 'updateVisibleMenuWithBlock:', '[old.children arrayByAddingObject:action]', '[items removeObjectIdenticalTo:self.button]']:
            self.assertIn(part,UI)
        for no in ['requireGestureRecognizerToFail','dismissMenu','removeAllObjects','setGestureRecognizers','setLongPress','[web setInteraction']:
            self.assertNotIn(no,UI)
    def test_bound_identity_geometry_and_late_callbacks(self):
        for part in ['op.web!=web','![op.token isEqual:token]','![self.token isEqual:token]','self.prompt!=prompt','self.generation!=WUContextGeneration()','[web.URL isEqual:self.article]','web.pageZoom!=1','s.zoomScale!=1','s.adjustedContentInset','CATransform3DIsIdentity','contentOffset','@"URL",@"loading",@"bounds"','[self.fetch cancel]','UIApplicationWillResignActiveNotification']:
            self.assertIn(part,UI)
        self.assertIn('[self verify:@"read"',UI)
        self.assertIn('confirmed:op.reading',UI)
        self.assertIn('live.reading=YES',UI)
        self.assertIn('取消所选图',UI)
    def test_one_image_no_page_enumeration_or_canvas_flattening(self):
        self.assertEqual(DOM.count('document.elementFromPoint(x,y)'),1)
        for part in ['img.currentSrc','old.img!==img','old.src!==src','old.doc!==document','old.time!==performance.timeOrigin','metrics.some','getRootNode()!==document','bytes:mode===\'read\'&&direct?src:null']:
            self.assertIn(part,DOM)
        for no in ['querySelectorAll','document.images','getElementsBy','fetch(', 'XMLHttpRequest','canvas','toDataURL','postMessage']:
            self.assertNotIn(no,DOM)
        self.assertIn('inFrame:nil inContentWorld:[WKContentWorld worldWithName:',UI)
    def test_request_gate_no_account_credential_transport(self):
        for part in ['!confirmed','!current()', 'WUArticleImageURL(url,article)','ephemeralSessionConfiguration','HTTPCookieStorage=nil','HTTPShouldSetCookies=NO','URLCredentialStorage=nil','URLCache=nil','HTTPAdditionalHeaders=@{}','HTTPShouldHandleCookies=NO','mainDocumentURL=nil','r.HTTPBody=nil','timeoutIntervalForResource=15','self.redirects>2','completionHandler([self request:request.URL])','ByteLimit-self.bytes.length','http.statusCode==200','NSURLSessionAuthChallengeCancelAuthenticationChallenge','self.completion=nil; self.current=nil;']:
            self.assertIn(part,NET)
        for no in ['sharedSession','sharedHTTPCookieStorage','WUCurrentAccount','Authorization', 'Cookie:', 'Referer', 'dataWithContentsOfURL:', 'NSLog','credentialForTrust','NSURLSessionAuthChallengeUseCredential']:
            self.assertNotIn(no,NET)
        for p in (ROOT/'Sources').glob('*'):
            if p.name not in {'WUArticleImageFetch.h','WUArticleImageFetch.m'}:
                self.assertNotIn('NSURLSession',p.read_text(),p.name)
    def test_native_editor_reused_no_sender(self):
        self.assertIn('WUOpenConfirmedImageDataEditor',UI)
        self.assertIn('WUImageEntryValidateData(data)',UI)
        self.assertEqual(IMAGE.count('pushViewController:editor animated:YES'),1)
        self.assertIn('if(self.dataCurrent)',IMAGE)
        self.assertIn('sourceCurrent(self.editor!=nil)',IMAGE)
        self.assertIn('[self.dataCurrent copy]',IMAGE)
        self.assertIn('[stack removeObjectIdenticalTo:editor]',IMAGE)
        for no in ['setDelegate:', 'EmoticonCustomManageAddLogic','startAddEmoticonWithWrap:', 'AddEmoticonMsg:', '添加成功','UIImagePNGRepresentation']:
            self.assertNotIn(no,UI)
        self.assertIn('GIF/APNG不支持',UI)
    def test_exact_production_js_in_synthetic_dom(self):
        node=shutil.which('node')
        if not node: self.skipTest('Node unavailable; native suite remains required')
        script=''.join(json.loads(line[1:].rstrip(';')) for line in DOM.splitlines() if line.startswith('@"'))
        subprocess.run([node,str(ROOT/'tests/article_image_dom.js')],input=script,text=True,check=True)

if __name__=='__main__': unittest.main(verbosity=2)
