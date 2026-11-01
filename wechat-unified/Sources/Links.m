#import "WU.h"
static NSURL *SafeURL(NSURL *url) {
    if(!url || url.absoluteString.length>4096) return nil;
    NSURLComponents *c=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if(![@[@"http",@"https"] containsObject:c.scheme.lowercaseString] || !c.host.length || c.user.length || c.password.length) return nil;
    if([c.host rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return nil;
    return c.URL;
}
static void Warn(UIViewController *owner,NSURL *url) {
    url=SafeURL(url); if(!url) return;
    NSString *message=[NSString stringWithFormat:@"目标域名：%@\n\n%@\n\n将交给系统默认浏览器（不一定是 Safari）。识别不代表安全；不会关闭微信或系统的风险检查。",url.host,url.absoluteString];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认外部打开" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL ok) {
            if(ok) return;
            dispatch_async(dispatch_get_main_queue(), ^{ UIAlertController *e=[UIAlertController alertControllerWithTitle:@"未能打开" message:@"系统拒绝或没有可用浏览器。未重试，也未绕过风险检查。" preferredStyle:UIAlertControllerStyleAlert]; [e addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [owner presentViewController:e animated:YES completion:nil]; });
        }];
    }]];
    [owner presentViewController:a animated:YES completion:nil];
}
void WUShowLinks(UIViewController *owner) {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"识别链接" message:@"手动输入或粘贴文字；不会自动读取剪贴板，也不保存搜索或链接历史。限 8192 字符。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"https://example.com"; f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert=a;
    [a addAction:[UIAlertAction actionWithTitle:@"识别" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text=weakAlert.textFields.firstObject.text ?: @"";
        NSMutableArray<NSURL *> *urls=[NSMutableArray array];
        if(text.length<=8192) {
            NSDataDetector *d=[NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL];
            for(NSTextCheckingResult *r in [d matchesInString:text options:0 range:NSMakeRange(0,text.length)]) {
                NSURL *u=SafeURL(r.URL); if(u && ![urls containsObject:u]) [urls addObject:u]; if(urls.count==10) break;
            }
        }
        if(urls.count==1) { Warn(owner,urls.firstObject); return; }
        UIAlertController *list=[UIAlertController alertControllerWithTitle:urls.count?@"选择链接":@"未发现可用 HTTP(S) 链接" message:urls.count?@"最多列出 10 个；不会自动访问。":@"不接受超长输入、用户名密码或非网页协议。" preferredStyle:UIAlertControllerStyleAlert];
        for(NSURL *u in urls) [list addAction:[UIAlertAction actionWithTitle:u.absoluteString style:UIAlertActionStyleDefault handler:^(UIAlertAction *b){ Warn(owner,u); }]];
        [list addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [owner presentViewController:list animated:YES completion:nil];
    }]];
    [owner presentViewController:a animated:YES completion:nil];
}
