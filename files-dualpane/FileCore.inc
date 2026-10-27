// Public Foundation transfer/bookmark core; also compiled unchanged by host fixtures.
static NSError *FPFileError(NSString *message) {
    return [NSError errorWithDomain:@"FilesDualPane" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL FPDirectory(NSURL *url, NSError **error) {
    NSNumber *directory=nil;
    if(!url.isFileURL) { if(error) *error=FPFileError(@"该位置未提供可访问的文件 URL。"); return NO; }
    if(![url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:error]) return NO;
    if(!directory.boolValue) { if(error) *error=FPFileError(@"目标不是文件夹。"); return NO; }
    return YES;
}
static BOOL FPReadyURL(NSURL *url, NSError **error) {
    if(![url checkResourceIsReachableAndReturnError:error]) return NO;
    NSString *status=nil;
    if(![url getResourceValue:&status forKey:NSURLUbiquitousItemDownloadingStatusKey error:error]) return NO;
    if(status && ![status isEqual:NSURLUbiquitousItemDownloadingStatusCurrent]) {
        if(error) *error=FPFileError(@"iCloud 项目尚未就绪，请先在 Files 下载后重试。"); return NO;
    }
    return YES;
}
static NSError *FPTransferOne(NSURL *source, NSURL *folder, BOOL move) {
    if(!source.isFileURL || !folder.isFileURL) return FPFileError(@"文件提供商未提供文件 URL，未执行操作。");
    NSURL *target=[folder URLByAppendingPathComponent:source.lastPathComponent];
    NSString *src=source.URLByResolvingSymlinksInPath.path, *dst=target.URLByResolvingSymlinksInPath.path;
    if(!src.length || !dst.length || [dst isEqual:src] || [dst hasPrefix:[src stringByAppendingString:@"/"]]) return FPFileError(@"不能操作到自身或自身的子目录。");
    BOOL sourceScope=[source startAccessingSecurityScopedResource], targetScope=[folder startAccessingSecurityScopedResource];
    __block NSError *failure=nil; __block BOOL completed=NO;
    NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSError *coordinationError=nil;
    void (^access)(NSURL *,NSURL *)=^(NSURL *from,NSURL *to){
        if(!FPDirectory(folder,&failure) || !FPReadyURL(from,&failure)) return;
        // Foundation copy/move refuse existing destinations; this check gives a clear error.
        if([[NSFileManager defaultManager] fileExistsAtPath:to.path]) { failure=FPFileError(@"目标存在同名项目；未覆盖，源项目保留。"); return; }
        if(move) {
            [coordinator itemAtURL:from willMoveToURL:to error:&failure];
            if(failure) return;
            completed=[[NSFileManager defaultManager] moveItemAtURL:from toURL:to error:&failure];
            if(completed) [coordinator itemAtURL:from didMoveToURL:to];
        } else completed=[[NSFileManager defaultManager] copyItemAtURL:from toURL:to error:&failure];
    };
    if(move) [coordinator coordinateWritingItemAtURL:source options:NSFileCoordinatorWritingForMoving writingItemAtURL:target options:0 error:&coordinationError byAccessor:access];
    else [coordinator coordinateReadingItemAtURL:source options:0 writingItemAtURL:target options:0 error:&coordinationError byAccessor:access];
    if(sourceScope) [source stopAccessingSecurityScopedResource];
    if(targetScope) [folder stopAccessingSecurityScopedResource];
    return coordinationError ?: failure ?: (completed ? nil : FPFileError(@"文件协调未完成；未确认成功。"));
}
static NSData *FPHomeBookmark(NSURL *url, NSError **error) {
    BOOL scope=[url startAccessingSecurityScopedResource];
    NSData *data=nil;
    if(FPDirectory(url,error) && FPReadyURL(url,error)) data=[url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark includingResourceValuesForKeys:nil relativeToURL:nil error:error];
    if(scope) [url stopAccessingSecurityScopedResource];
    return data;
}
static NSURL *FPResolveHome(id data, NSError **error) {
    if(![data isKindOfClass:NSData.class]) { if(error) *error=FPFileError(@"首页书签无效。"); return nil; }
    BOOL stale=NO;
    NSURL *url=[NSURL URLByResolvingBookmarkData:data options:NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:error];
    if(stale || !url.isFileURL) { if(error) *error=FPFileError(@"首页书签已失效，请重新设置。"); return nil; }
    return url;
}
