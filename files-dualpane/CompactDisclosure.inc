// Only public disclosure accessories, never navigation/back or provider status controls.
static char FPDisclosureKey;
static void FPDisclosure(UICollectionViewCell *cell, BOOL compact) {
    if(![cell isKindOfClass:UICollectionViewListCell.class]) return;
    UICollectionViewListCell *list=(id)cell;
    NSDictionary *saved=objc_getAssociatedObject(list,&FPDisclosureKey);
    if(!compact) {
        if(saved) {
            if(list.accessories==saved[@"filtered"] && [list.accessories isEqual:saved[@"filtered"]]) list.accessories=saved[@"original"];
            objc_setAssociatedObject(list,&FPDisclosureKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    NSMutableArray *kept=[NSMutableArray new], *removed=[NSMutableArray new];
    [list.accessories enumerateObjectsUsingBlock:^(UICellAccessory *item,NSUInteger index,BOOL *stop){
        if([item isKindOfClass:UICellAccessoryDisclosureIndicator.class]) [removed addObject:@[@(index),item]];
        else [kept addObject:item];
    }];
    if(!removed.count) return;
    NSArray *original=list.accessories;
    list.accessories=kept;
    objc_setAssociatedObject(list,&FPDisclosureKey,@{@"original":original,@"filtered":list.accessories},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Cell accessibility traits/actions and all delegate callbacks remain native.
}
