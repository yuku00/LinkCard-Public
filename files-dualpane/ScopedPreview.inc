static NSError *CheckPreviewURLs(NSArray<NSURL *> *urls) {
    __block NSError *failure=nil;
    for(NSURL *url in urls) {
        NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
        NSError *coordinationError=nil;
        [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&coordinationError byAccessor:^(NSURL *coordinatedURL){
            if(![coordinatedURL checkResourceIsReachableAndReturnError:&failure]) return;
            NSString *status=nil; [coordinatedURL getResourceValue:&status forKey:NSURLUbiquitousItemDownloadingStatusKey error:nil];
            if(status && ![status isEqual:NSURLUbiquitousItemDownloadingStatusCurrent]) failure=[NSError errorWithDomain:@"FilesDualPane" code:1 userInfo:@{NSLocalizedDescriptionKey:@"文件尚未下载完成。请先在 Files 中下载，再预览。"}];
        }];
        if(coordinationError) failure=coordinationError;
        if(failure) break;
    }
    return failure;
}
@interface FPScopedPreview : QLPreviewController <QLPreviewControllerDataSource>
@property(nonatomic,copy) NSArray<NSURL *> *urls;
@property(nonatomic,copy) NSArray<NSURL *> *scopes;
@end
@implementation FPScopedPreview
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller { return self.urls.count; }
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index { return self.urls[index]; }
- (void)dealloc { for(NSURL *url in _scopes) [url stopAccessingSecurityScopedResource]; }
@end
