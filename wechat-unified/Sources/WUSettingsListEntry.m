#import "WU.h"
#import <objc/message.h>
#import <objc/runtime.h>

static char sectionKey, entryKey;
static BOOL Match(id o, NSString *name, const char *ret, NSArray *args) {
    return o && WUMatches(class_getInstanceMethod(object_getClass(o),NSSelectorFromString(name)),ret,args);
}
static id Get(id o,NSString *name) { return Match(o,name,"@",@[]) ? ((id(*)(id,SEL))objc_msgSend)(o,NSSelectorFromString(name)) : nil; }
@interface WUSettingsRowTarget : NSObject
@property(nonatomic,weak) UIViewController *owner;
- (void)open;
@end
@implementation WUSettingsRowTarget
- (void)open { UIViewController *v=self.owner; if(v.isViewLoaded && v.view.window && v.navigationController.topViewController==v && !v.presentedViewController) WUShowSettings(v); }
@end
void WUEnsureSettingsListRow(UIViewController *owner) {
    if (!NSThread.isMainThread || object_getClass(owner)!=NSClassFromString(@"NewSettingViewController") || !owner.isViewLoaded || !owner.view.window) return;
    Ivar ivar=class_getInstanceVariable(object_getClass(owner),"m_tableViewMgr");
    if(ivar && ivar_getTypeEncoding(ivar)[0]=='@') {
        id manager=object_getIvar(owner,ivar);
        Class sectionClass=NSClassFromString(@"WCTableViewSectionManager"), cellClass=NSClassFromString(@"WCTableViewNormalCellManager");
        NSString *factory=@"normalCellForSel:target:title:accessoryType:";
        id table=Get(manager,@"getTableView"), sections=Get(manager,@"sections");
        id old=objc_getAssociatedObject(owner,&sectionKey);
        if(object_getClass(manager)==NSClassFromString(@"WCTableViewManager") && [table isKindOfClass:UITableView.class] && [table isDescendantOfView:owner.view] && [sections isKindOfClass:NSArray.class] &&
           Match(sectionClass,@"defaultSection","@",@[]) && Match(cellClass,factory,"@",@[@":",@"@",@"@",@"q"]) &&
           Match(manager,@"insertSection:At:","v",@[@"@",[NSString stringWithUTF8String:@encode(unsigned int)]]) && WUMatches(class_getInstanceMethod(sectionClass,NSSelectorFromString(@"addCell:")),"v",@[@"@"])) {
            if(old && [sections indexOfObjectIdenticalTo:old]!=NSNotFound) return;
            WUSettingsRowTarget *target=objc_getAssociatedObject(owner,&entryKey);
            if(!target) { target=[WUSettingsRowTarget new]; target.owner=owner; objc_setAssociatedObject(owner,&entryKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            id section=((id(*)(id,SEL))objc_msgSend)(sectionClass,NSSelectorFromString(@"defaultSection"));
            id cell=((id(*)(id,SEL,SEL,id,id,long long))objc_msgSend)(cellClass,NSSelectorFromString(factory),@selector(open),target,@"微信整合",1LL);
            if(!section || object_getClass(section)!=sectionClass || !cell || object_getClass(cell)!=cellClass || Get(manager,@"sections")!=sections || object_getIvar(owner,ivar)!=manager) return;
            ((void(*)(id,SEL,id))objc_msgSend)(section,NSSelectorFromString(@"addCell:"),cell);
            ((void(*)(id,SEL,id,unsigned int))objc_msgSend)(manager,NSSelectorFromString(@"insertSection:At:"),section,0U);
            objc_setAssociatedObject(owner,&sectionKey,section,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [(UITableView *)table reloadData];
            return;
        }
    }
    ivar=class_getInstanceVariable(object_getClass(owner),"m_tableViewInfo");
    if(!ivar || ivar_getTypeEncoding(ivar)[0]!='@') return;
    id manager=object_getIvar(owner,ivar);
    if(!manager || object_getClass(manager)!=NSClassFromString(@"MMTableViewInfo")) return;
    id table=Get(manager,@"getTableView"), sections=Get(manager,@"sections");
    if(![table isKindOfClass:UITableView.class] || ![table isDescendantOfView:owner.view] || ![sections isKindOfClass:NSArray.class]) return;
    id old=objc_getAssociatedObject(owner,&sectionKey);
    if(old && [sections indexOfObjectIdenticalTo:old]!=NSNotFound) return;
    Class sectionClass=NSClassFromString(@"MMTableViewSectionInfo"), cellClass=NSClassFromString(@"MMTableViewCellInfo");
    NSString *factory=@"normalCellForSel:target:title:accessoryType:";
    if(!Match(sectionClass,@"sectionInfoDefaut","@",@[]) || !Match(cellClass,factory,"@",@[@":",@"@",@"@",@"q"]) ||
       !Match(manager,@"addSection:","v",@[@"@"]) || !WUMatches(class_getInstanceMethod(sectionClass,NSSelectorFromString(@"addCell:")),"v",@[@"@"])) return;
    WUSettingsRowTarget *target=objc_getAssociatedObject(owner,&entryKey);
    if(!target) { target=[WUSettingsRowTarget new]; target.owner=owner; objc_setAssociatedObject(owner,&entryKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    id section=((id(*)(id,SEL))objc_msgSend)(sectionClass,NSSelectorFromString(@"sectionInfoDefaut"));
    id cell=((id(*)(id,SEL,SEL,id,id,long long))objc_msgSend)(cellClass,NSSelectorFromString(factory),@selector(open),target,@"微信整合",1LL);
    if(!section || object_getClass(section)!=sectionClass || !cell || object_getClass(cell)!=cellClass || Get(manager,@"sections")!=sections || object_getIvar(owner,ivar)!=manager) return;
    ((void(*)(id,SEL,id))objc_msgSend)(section,NSSelectorFromString(@"addCell:"),cell);
    ((void(*)(id,SEL,id))objc_msgSend)(manager,NSSelectorFromString(@"addSection:"),section);
    objc_setAssociatedObject(owner,&sectionKey,section,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [(UITableView *)table reloadData];
}
