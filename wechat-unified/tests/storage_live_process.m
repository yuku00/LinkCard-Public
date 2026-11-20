#import <Foundation/Foundation.h>
#import "VoicePackLogic.h"
#import "RepositoryLogic.h"
#include "WUStorageMigration.h"
#include "WUStorageSelection.h"
#include <sys/stat.h>
#define CHECK(x) do { if(!(x)) { fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x); return 1; } } while(0)
static NSData *fixture(void) {
    NSString *s=[NSString stringWithContentsOfFile:@"tests/fixtures/synthetic.amr.hex" encoding:NSUTF8StringEncoding error:NULL];
    NSString *h=[[s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""]; NSMutableData *d=[NSMutableData data];
    for(NSUInteger i=0;i<h.length;i+=2) { unsigned n=0; if(![[NSScanner scannerWithString:[h substringWithRange:NSMakeRange(i,2)]] scanHexInt:&n]) return nil; unsigned char b=n; [d appendBytes:&b length:1]; } return d;
}
static NSDictionary *entry(NSString *text,NSString *identifier) { return @{@"id":identifier,@"name":@"synthetic",@"parts":@[@{@"kind":@"text",@"text":text}]}; }
int main(int argc,char **argv) { @autoreleasepool {
    (void)wu_backup_tar; (void)wu_storage_prepare;
    CHECK(argc==3); NSString *mode=[NSString stringWithUTF8String:argv[1]], *path=[NSString stringWithUTF8String:argv[2]];
    int docs=open(path.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); CHECK(docs>=0);
    if([mode isEqual:@"create"]) { CHECK(wu_selection_create(docs,"12345678-ABCD-4ABC-8ABC-123456789ABC")); close(docs); puts("CREATE OK"); return 0; }
    char name[128]={0}; int selected=wu_selection_open(docs,name,sizeof(name)); close(docs);
    if([mode isEqual:@"invalid"]) { CHECK(selected==-1); puts("INVALID PROTECTED"); return 0; }
    if([mode isEqual:@"absent"]) { CHECK(selected==0); puts("ABSENT"); return 0; }
    CHECK(selected==1);
    NSURL *root=[[NSURL fileURLWithPath:path isDirectory:YES] URLByAppendingPathComponent:[NSString stringWithUTF8String:name] isDirectory:YES];
    root=[root URLByAppendingPathComponent:@"WeChatUnified" isDirectory:YES];
    NSURL *v=[root URLByAppendingPathComponent:@"VoicePacks" isDirectory:YES], *repo=[root URLByAppendingPathComponent:@"Repository" isDirectory:YES];
    WUVoicePackStore *store=[[WUVoicePackStore alloc] initWithRoot:v account:@"a"]; CHECK(store);
    NSData *audio=fixture(); CHECK(audio.length>0); BOOL (^yes)(void)=^BOOL{return YES;}; NSError *error=nil;
    NSString *id1=@"12345678-ABCD-4ABC-8ABC-123456789ABA", *id2=@"12345678-ABCD-4ABC-8ABC-123456789ABB";
    NSDictionary *one=entry(@"first synthetic text",id1), *two=entry(@"second synthetic text",id2);
    if([mode isEqual:@"write1"]) {
        CHECK([store load:&error].count==0 && !error); CHECK(WURepositoryLoad(repo,@"a",&error).count==0 && !error);
        CHECK(![[WUVoicePackStore alloc] initWithRoot:v account:@""]); CHECK(WURepositoryLoad(repo,@"",&error)==nil && error); error=nil;
        WUVoicePackStore *other=[[WUVoicePackStore alloc] initWithRoot:v account:@"b"]; CHECK(other && [other load:&error].count==0 && !error);
        NSURL *input=[[NSURL fileURLWithPath:path isDirectory:YES] URLByAppendingPathComponent:@"synthetic.amr"]; CHECK([audio writeToURL:input atomically:YES]);
        CHECK([store importFile:input name:@"first" current:yes error:&error]); CHECK(WURepositorySave(repo,@"a",@[one],&error)); puts("WRITE1 OK"); return 0;
    }
    if([mode isEqual:@"repo-bad"] || [mode isEqual:@"repo-denied"]) {
        CHECK(WURepositoryLoad(repo,@"a",&error)==nil && error); puts("REPOSITORY READ FAILURE PROTECTED"); return 0;
    }
    if([mode isEqual:@"source-missing"]) {
        NSURL *input=[[NSURL fileURLWithPath:path isDirectory:YES] URLByAppendingPathComponent:@"synthetic.amr"];
        CHECK(![store importFile:input name:@"missing source" current:yes error:&error]); CHECK(error); puts("MISSING SOURCE PROTECTED"); return 0;
    }
    if([mode isEqual:@"missing"] || [mode isEqual:@"bad"] || [mode isEqual:@"denied"]) {
        CHECK([store load:&error]==nil && error); error=nil;
        NSURL *input=[[NSURL fileURLWithPath:path isDirectory:YES] URLByAppendingPathComponent:@"synthetic.amr"];
        CHECK(![store importFile:input name:@"must not overwrite" current:yes error:&error]); puts("VOICE FAILURE PROTECTED"); return 0;
    }
    NSArray *rows=[store load:&error]; CHECK(rows && !error && rows.count>=1); CHECK([rows[0][@"data"] isEqual:audio]);
    NSArray *items=WURepositoryLoad(repo,@"a",&error); CHECK(items && !error && [items[0] isEqual:one]);
    CHECK(WURepositoryLoad(repo,@"b",&error).count==0 && !error);
    WUVoicePackStore *other=[[WUVoicePackStore alloc] initWithRoot:v account:@"b"]; CHECK(other && [other load:&error].count==0 && !error);
    if([mode isEqual:@"write2"]) {
        CHECK(rows.count==1 && items.count==1);
        NSURL *input=[[NSURL fileURLWithPath:path isDirectory:YES] URLByAppendingPathComponent:@"synthetic.amr"];
        CHECK([store importFile:input name:@"second" current:yes error:&error]); CHECK(WURepositorySave(repo,@"a",@[one,two],&error)); puts("WRITE2 OK"); return 0;
    }
    if([mode isEqual:@"read2"]) { CHECK(rows.count==2 && [rows[1][@"data"] isEqual:audio]); CHECK(items.count==2 && [items[1] isEqual:two]); puts("READ2 OK"); return 0; }
    CHECK(0);
} return 0; }
