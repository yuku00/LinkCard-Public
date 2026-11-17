// Included by WUCapture.m and the synthetic UIKit helper tests.
#import <math.h>

static BOOL WUPageFiniteRect(CGRect r, BOOL scroll) {
    return isfinite(r.size.width) && isfinite(r.size.height) &&
        (scroll || (isfinite(r.origin.x) && isfinite(r.origin.y)));
}
static BOOL WUPageFiniteInsets(UIEdgeInsets i) {
    return isfinite(i.top) && isfinite(i.left) && isfinite(i.bottom) && isfinite(i.right);
}
static void WUPageAppendGeometry(NSMutableString *out, id obj) {
    @try {
        Class type=object_getClass(obj);
        const char *name=type ? class_getName(type) : NULL;
        BOOL exactUIKit=type==UIView.class || type==UIWindow.class || type==UIScrollView.class || type==UITableView.class || type==UICollectionView.class;
        BOOL target=name && (!strcmp(name,"MMTableView") || !strcmp(name,"NSKVONotifying_MMTableView") || !strcmp(name,"MMInputToolView") || !strcmp(name,"InputToolContainerView") || !strcmp(name,"InputToolViewBar") || !strcmp(name,"EmoticonMessageCellView") || !strcmp(name,"AppEmoticonMessageCellView"));
        if(!exactUIKit && !target) return;
        if(![obj isKindOfClass:UIView.class]) { [out appendString:@"  几何省略：白名单类不是 UIView。\n"]; return; }
        BOOL scroll=[obj isKindOfClass:UIScrollView.class];
        if(name && (!strcmp(name,"MMTableView") || !strcmp(name,"NSKVONotifying_MMTableView")) && !scroll) { [out appendString:@"  几何省略：表格白名单类不是 UIScrollView。\n"]; return; }
        UIView *view=(UIView *)obj;
        CGRect f=view.frame, b=view.bounds;
        UIEdgeInsets inset=UIEdgeInsetsZero, adjusted=UIEdgeInsetsZero;
        if(scroll) { UIScrollView *s=(UIScrollView *)view; inset=s.contentInset; adjusted=s.adjustedContentInset; }
        if(!WUPageFiniteRect(f,NO) || !WUPageFiniteRect(b,scroll) || (scroll && (!WUPageFiniteInsets(inset) || !WUPageFiniteInsets(adjusted)))) {
            [out appendString:@"  几何省略：非有限数值。\n"]; return;
        }
        // Fixed-width decimal formatting can expand huge finite values indefinitely.
        const CGFloat limit=10000000;
        if(fabs(f.origin.x)>limit || fabs(f.origin.y)>limit || fabs(f.size.width)>limit || fabs(f.size.height)>limit || fabs(b.size.width)>limit || fabs(b.size.height)>limit || (!scroll && (fabs(b.origin.x)>limit || fabs(b.origin.y)>limit)) || (scroll && (fabs(inset.top)>limit || fabs(inset.left)>limit || fabs(inset.bottom)>limit || fabs(inset.right)>limit || fabs(adjusted.top)>limit || fabs(adjusted.left)>limit || fabs(adjusted.bottom)>limit || fabs(adjusted.right)>limit))) {
            [out appendString:@"  几何省略：数值超限（截断）。\n"]; return;
        }
        [out appendFormat:@"  frame=(%.2f,%.2f,%.2f,%.2f)",f.origin.x,f.origin.y,f.size.width,f.size.height];
        if(scroll) [out appendFormat:@" bounds.size=(%.2f,%.2f)\n",b.size.width,b.size.height];
        else [out appendFormat:@" bounds=(%.2f,%.2f,%.2f,%.2f)\n",b.origin.x,b.origin.y,b.size.width,b.size.height];
        if(scroll) [out appendFormat:@"  contentInset=(%.2f,%.2f,%.2f,%.2f) adjustedContentInset=(%.2f,%.2f,%.2f,%.2f) [top,left,bottom,right]\n",inset.top,inset.left,inset.bottom,inset.right,adjusted.top,adjusted.left,adjusted.bottom,adjusted.right];
    } @catch (__unused NSException *exception) {
        [out appendString:@"  几何省略：类型检查或 getter 异常。\n"];
    }
}
