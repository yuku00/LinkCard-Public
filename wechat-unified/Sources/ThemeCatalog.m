#import "ThemeCatalog.h"
#import "ThemeArchive.h"
#import "ThemePrimitives.h"
static id Invalid(NSError **e, NSString *s) { if(e) *e=[NSError errorWithDomain:@"WeChatUnified.Theme" code:1 userInfo:@{NSLocalizedDescriptionKey:s}]; return nil; }
BOOL WUThemeSafePath(NSString *p) {
    if(![p isKindOfClass:NSString.class]||!p.length||[p lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>240||[p hasPrefix:@"/"]||[p containsString:@"\\"]||[p containsString:@":"]||[p rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return NO;
    for(NSString *part in [p componentsSeparatedByString:@"/"]) if(!part.length||[part hasPrefix:@"."]) return NO;
    return YES;
}
NSDictionary *WUThemeMergeFiles(NSDictionary *old,NSDictionary *incoming,BOOL replace,NSError **error) {
    NSMutableDictionary *out=[NSMutableDictionary dictionary],*folds=[NSMutableDictionary dictionary]; NSUInteger total=0;
    for(NSDictionary *set in @[old?:@{},incoming?:@{}]) for(NSString *p in [[set allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if(!WUThemeSafePath(p)||![set[p] isKindOfClass:NSData.class]||[set[p] length]>8*1024*1024) return Invalid(error,@"资源路径或大小无效");
        NSString *fold=p.precomposedStringWithCanonicalMapping.lowercaseString,*prior=folds[fold];
        if(prior) {
            if([out[prior] isEqual:set[p]]) continue;
            if(!replace) return Invalid(error,[NSString stringWithFormat:@"追加冲突：%@。原包未更改；请选择明确替换同路径。",p]);
            total-=[out[prior] length]; [out removeObjectForKey:prior];
        }
        total+=[set[p] length]; if(total>64*1024*1024) return Invalid(error,@"解包总量超过64MB");
        folds[fold]=p; out[p]=set[p];
    }
    if(!out.count||out.count>510) return Invalid(error,@"资源数量须为1–510");
    for(NSString *fold in folds) { NSString *parent=fold.stringByDeletingLastPathComponent; while(parent.length) { if(folds[parent]) return Invalid(error,@"目录与文件冲突"); parent=parent.stringByDeletingLastPathComponent; } }
    return out;
}
static NSString *ResourceKey(NSString *p) {
    NSString *s=p.precomposedStringWithCanonicalMapping.lowercaseString;
    if([@[@"png",@"jpg",@"jpeg",@"webp",@"heic",@"svg",@"car"] containsObject:s.pathExtension]) s=s.stringByDeletingPathExtension;
    if([s hasSuffix:@"@2x"]||[s hasSuffix:@"@3x"]) s=[s substringToIndex:s.length-3]; return s;
}
NSDictionary *WUThemeResourceIndex(NSArray<NSString *> *paths) {
    NSMutableDictionary *index=[NSMutableDictionary dictionary];
    for(NSString *p in [paths sortedArrayUsingSelector:@selector(compare:)]) {
        if(![@[@"png",@"jpg",@"jpeg",@"webp",@"heic",@"svg"] containsObject:p.pathExtension.lowercaseString]) continue;
        NSString *full=ResourceKey(p),*base=full.lastPathComponent;
        NSArray *parts=[full componentsSeparatedByString:@"/"]; NSString *variant=nil;
        for(NSString *component in parts) if([@[@"dark",@"light"] containsObject:component]) variant=component;
        NSString *shortKey=variant?[variant stringByAppendingPathComponent:base]:base;
        for(NSString *key in [NSOrderedSet orderedSetWithArray:@[full,shortKey]]) { if(!index[key]) index[key]=[NSMutableArray array]; [index[key] addObject:p]; }
    } return index;
}
NSArray *WUThemeCandidates(NSString *name,BOOL dark,NSDictionary *aliases) {
    NSString *key=ResourceKey(name); NSMutableOrderedSet *out=[NSMutableOrderedSet orderedSet];
    NSString *alias=aliases[key]?:aliases[key.lastPathComponent];
    for(NSString *raw in (alias?@[alias,key]:@[key])) {
        NSString *k=ResourceKey(raw),*base=k; BOOL highlight=[base hasSuffix:@"_hl"]||[base hasSuffix:@"_hl_dark"];
        BOOL explicitDark=[base containsString:@"_dark"]||[base hasPrefix:@"dark/"];
        if(explicitDark) [out addObject:k];
        if([base hasSuffix:@"_hl_dark"]) base=[[base substringToIndex:base.length-8] stringByAppendingString:@"_dark_hl"];
        if([base hasSuffix:@"_dark_hl"]) base=[[base substringToIndex:base.length-8] stringByAppendingString:@"_hl"];
        else if([base hasSuffix:@"_dark"]) base=[base substringToIndex:base.length-5];
        NSString *stem=highlight?[base substringToIndex:base.length-3]:base;
        if([stem hasSuffix:@"_new"]) stem=[stem substringToIndex:stem.length-4];
        if([stem hasSuffix:@"_white"]) stem=[stem substringToIndex:stem.length-6];
        if(dark||explicitDark) {
            [out addObject:[@"dark" stringByAppendingPathComponent:base]];
            [out addObject:[stem stringByAppendingString:highlight?@"_dark_hl":@"_dark"]];
            if(highlight) [out addObject:[stem stringByAppendingString:@"_hl_dark"]];
        } else [out addObject:[@"light" stringByAppendingPathComponent:base]];
        [out addObject:base];
        [out addObject:[stem stringByAppendingString:highlight?@"_hl":@""]];
        // Legacy alternatives are lower priority; never discard highlighted state for a normal asset first.
        [out addObject:[stem stringByAppendingString:highlight?@"_new_hl":@"_new"]];
        if(!highlight) [out addObject:[stem stringByAppendingString:@"_white"]];
        [out addObject:k];
    } return out.array;
}
NSString *WUThemeBestPath(NSArray *paths,double scale) {
    NSString *best=nil; double score=HUGE_VAL;
    for(NSString *p in paths) { NSString *n=p.stringByDeletingPathExtension.lowercaseString; double s=[n hasSuffix:@"@3x"]?3:([n hasSuffix:@"@2x"]?2:1); double value=WUThemeScaleScore(s,scale); if(value<score||(value==score&&p.pathComponents.count<best.pathComponents.count)) { best=p; score=value; } } return best;
}
BOOL WUValidThemeOptions(id v) {
    if(![v isKindOfClass:NSDictionary.class]) return NO;
    for(NSString *k in v) if(![@[@"sort",@"ascending",@"pinned",@"cards"] containsObject:k]) return NO;
    if(v[@"sort"]&&![@[@"name",@"imported",@"modified",@"size"] containsObject:v[@"sort"]]) return NO;
    for(NSString *k in @[@"ascending",@"cards"]) if(v[k]&&![v[k] isKindOfClass:NSNumber.class]) return NO;
    if(v[@"pinned"]) { if(![v[@"pinned"] isKindOfClass:NSArray.class]||[v[@"pinned"] count]>510) return NO; NSMutableSet *seen=[NSMutableSet set]; for(id s in v[@"pinned"]) { if(![s isKindOfClass:NSString.class]||![[NSUUID alloc] initWithUUIDString:s]||[seen containsObject:s]) return NO; [seen addObject:s]; } }
    return YES;
}
NSArray *WUThemeSortedPacks(NSArray *packs,NSDictionary *options) {
    if(!WUValidThemeOptions(options)) options=@{};
    NSString *key=options[@"sort"]?:@"name"; BOOL asc=options[@"ascending"]?[options[@"ascending"] boolValue]:YES; NSArray *pins=options[@"pinned"]?:@[];
    return [packs sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        NSUInteger x=[pins indexOfObject:a[@"id"]],y=[pins indexOfObject:b[@"id"]];
        if(x!=y) return x<y?NSOrderedAscending:NSOrderedDescending;
        NSComparisonResult r=[key isEqual:@"name"]?[a[@"name"] localizedStandardCompare:b[@"name"]]:[(a[key]?:@0) compare:(b[key]?:@0)];
        if(!r) r=[a[@"id"] compare:b[@"id"]]; return asc?r:-r;
    }];
}
NSDictionary *WUThemeReadDescriptor(NSData *d,NSError **error) {
    if(!d) return @{};
    if(d.length>65536) return Invalid(error,@"wu-theme.json超过64KB");
    id v=[NSJSONSerialization JSONObjectWithData:d options:0 error:error]; if(![v isKindOfClass:NSDictionary.class]||![v[@"version"] isEqual:@1]) return Invalid(error,@"wu-theme.json须version=1");
    id aliases=v[@"aliases"]?:@{}; if(![aliases isKindOfClass:NSDictionary.class]||[aliases count]>256) return Invalid(error,@"aliases须为最多256项的字典");
    NSMutableDictionary *clean=[NSMutableDictionary dictionary];
    for(id k in aliases) { if(!WUThemeSafePath(k)||!WUThemeSafePath(aliases[k])||[aliases[k] length]>240||clean[ResourceKey(k)]) return Invalid(error,@"别名路径无效或规范名重复"); clean[ResourceKey(k)]=ResourceKey(aliases[k]); }
    id catalogs=v[@"catalogAssets"]?:@{};
    if(![catalogs isKindOfClass:NSDictionary.class]||[catalogs count]>64) return Invalid(error,@"catalogAssets须为CAR相对路径到资源名数组的字典");
    for(id path in catalogs) { id names=catalogs[path]; if(!WUThemeSafePath(path)||![path.pathExtension.lowercaseString isEqual:@"car"]||![names isKindOfClass:NSArray.class]||![names count]||[names count]>256) return Invalid(error,@"CAR资源名列表无效"); for(id name in names) if(!WUThemeSafePath(name)) return Invalid(error,@"CAR资源名无效"); }
    NSMutableDictionary *result=[v mutableCopy]; result[@"aliases"]=clean; return result;
}
NSArray *WUSurfaceRoles(void) { return @[@"inputBorder",@"noticeBorder",@"searchSurface",@"referSurface",@"plusSurface",@"toastSurface",@"timeSurface",@"swipeSurface",@"fileSurface",@"emoticonSurface"]; }
BOOL WUValidSurfaceStyles(id v) {
    if(![v isKindOfClass:NSDictionary.class]||[v count]>10) return NO;
    NSDictionary *ranges=@{@"radius":@[@0,@80],@"borderWidth":@[@0,@8],@"fontSize":@[@8,@48],@"fontWeight":@[@(-1),@1],@"opacity":@[@0,@1]};
    for(NSString *role in v) {
        id style=v[role]; if(![WUSurfaceRoles() containsObject:role]||![style isKindOfClass:NSDictionary.class]) return NO;
        for(NSString *k in style) {
            id value=style[k]; NSArray *r=ranges[k];
            if(r) { if(![value isKindOfClass:NSNumber.class]||!WUStyleNumber([value doubleValue],[r[0] doubleValue],[r[1] doubleValue])) return NO; }
            else if([@[@"background",@"backgroundDark",@"text",@"textDark",@"tint",@"tintDark",@"border",@"borderDark"] containsObject:k]) { double c[4]; if(![value isKindOfClass:NSString.class]||!WUParseRGBA([value UTF8String],c)) return NO; }
            else if([k isEqual:@"fontName"]) { if(![value isKindOfClass:NSString.class]||[value length]>100) return NO; }
            else return NO;
        }
    } return YES;
}
