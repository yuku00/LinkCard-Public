#import "WU.h"
extern BOOL WUMergeSpacingAvailable(void);
void WUShowMergeSpacingSettings(UIViewController *owner) {
    NSNumber *current=WUValue(@"mergeSpacing");
    NSString *status=([current isKindOfClass:NSNumber.class] && current.doubleValue>=0 && current.doubleValue<=30)?[NSString stringWithFormat:@"当前目标间距：%@ pt。",current]:@"当前关闭，使用微信原行高。";
    NSString *message=[status stringByAppendingString:@"\n仅对已启用头像合并且识别为同一发送者的相邻消息生效；按微信基准间距缩减行高，不会增加行高。长文本、复杂行或接口不兼容时保留原高。关闭恢复原高；不修改聊天记录。实际效果须真机验证。"];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"合并消息间距" message:message preferredStyle:UIAlertControllerStyleAlert];
    void (^save)(NSInteger)=^(NSInteger value) {
        if(value>=0 && !WUMergeSpacingAvailable()) return;
        if(!WUSave(@"mergeSpacing",@(value))) {
            UIAlertController *failure=[UIAlertController alertControllerWithTitle:@"未保存" message:@"配置不可写或保存失败，原设置保留。" preferredStyle:UIAlertControllerStyleAlert];
            [failure addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
            dispatch_async(dispatch_get_main_queue(),^{ [owner presentViewController:failure animated:YES completion:nil]; });
        }
    };
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭 · 恢复原高" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){ save(-1); }]];
    for(NSNumber *n in @[@0,@4,@8,@12,@16,@20,@24,@30]) {
        UIAlertAction *action=[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ pt",n] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *selected){ save(n.integerValue); }];
        action.enabled=WUMergeSpacingAvailable(); [alert addAction:action];
    }
    if(!WUMergeSpacingAvailable()) alert.message=[message stringByAppendingString:@"\n当前宿主接口不可用，无法开启。"];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [owner presentViewController:alert animated:YES completion:nil];
}
