#if defined(__APPLE__)
#define _DARWIN_C_SOURCE 1
#endif
#define _POSIX_C_SOURCE 200809L
#define _XOPEN_SOURCE 700
#include "EmoticonLibrarySafety.h"
#include <assert.h>
#include <dirent.h>
#include <limits.h>
static int checks;
#define CHECK(x) do { assert(x); ++checks; } while(0)
typedef struct { int calls; int invalidate; } Guard;
static bool valid(void *p) { Guard *g=p; return ++g->calls!=g->invalidate; }
static void read_equal(const char *path,const char *data) {
    FILE *f=fopen(path,"rb"); CHECK(f); char buffer[128]={0}; size_t n=fread(buffer,1,sizeof buffer,f); fclose(f); CHECK(n==strlen(data)); CHECK(!memcmp(buffer,data,n));
}
int main(void) {
    char temporaryRoot[]="/tmp/wu-emoticons-XXXXXX"; CHECK(mkdtemp(temporaryRoot));
    char root[PATH_MAX]; CHECK(realpath(temporaryRoot,root));
    char directory[PATH_MAX], index[PATH_MAX], source[PATH_MAX], linkdir[PATH_MAX], temp[PATH_MAX];
    CHECK(snprintf(directory,sizeof directory,"%s/account-a",root)>0); CHECK(mkdir(directory,0700)==0);
    CHECK(snprintf(index,sizeof index,"%s/index.plist",directory)>0);
    CHECK(snprintf(source,sizeof source,"%s/source.gif",root)>0);
    CHECK(snprintf(linkdir,sizeof linkdir,"%s/link",root)>0);
    const char *uuid="11111111-1111-4111-8111-111111111111";
    CHECK(snprintf(temp,sizeof temp,"%s/%s",directory,uuid)>0);
    Guard g={0,0}; const char *old="original-gif-bytes", *next="edited-index-not-source";
    CHECK(WUEmojiAtomicCommit(directory,uuid,old,strlen(old),valid,&g)); CHECK(g.calls==2); read_equal(index,old);
    g=(Guard){0,1}; CHECK(!WUEmojiAtomicCommit(directory,uuid,next,strlen(next),valid,&g)); read_equal(index,old); CHECK(access(temp,F_OK)!=0);
    g=(Guard){0,2}; CHECK(!WUEmojiAtomicCommit(directory,uuid,next,strlen(next),valid,&g)); read_equal(index,old); CHECK(access(temp,F_OK)!=0);
    g=(Guard){0,0}; CHECK(WUEmojiAtomicCommit(directory,uuid,next,strlen(next),valid,&g)); read_equal(index,next);
    CHECK(rename(index,source)==0); CHECK(symlink(source,index)==0); g=(Guard){0,0}; CHECK(!WUEmojiAtomicCommit(directory,uuid,old,strlen(old),valid,&g)); read_equal(source,next); CHECK(unlink(index)==0);
    CHECK(link(source,index)==0); g=(Guard){0,0}; CHECK(!WUEmojiAtomicCommit(directory,uuid,old,strlen(old),valid,&g)); read_equal(source,next); CHECK(unlink(index)==0);
    CHECK(symlink(directory,linkdir)==0); g=(Guard){0,0}; CHECK(!WUEmojiAtomicCommit(linkdir,uuid,old,strlen(old),valid,&g)); CHECK(unlink(linkdir)==0);
    FILE *f=fopen(temp,"wb"); CHECK(f); CHECK(fwrite("orphan",1,6,f)==6); fclose(f); g=(Guard){0,0}; CHECK(!WUEmojiAtomicCommit(directory,uuid,old,strlen(old),valid,&g)); read_equal(temp,"orphan"); CHECK(unlink(temp)==0);
    CHECK(!WUEmojiAtomicCommit(directory,"../index.plist",old,strlen(old),valid,&g));
    CHECK(!WUEmojiAtomicCommit(directory,uuid,old,64UL*1024*1024+1,valid,&g));
    CHECK(!WUEmojiAtomicCommit(directory,uuid,old,0,valid,&g));
    CHECK(!WUEmojiAtomicCommit(directory,uuid,old,strlen(old),NULL,&g));
    CHECK(WUEmojiOpenDirectory("relative")==-1); char traversal[PATH_MAX]; CHECK(snprintf(traversal,sizeof traversal,"%s/..",directory)>0); CHECK(WUEmojiOpenDirectory(traversal)==-1);
    CHECK(mkdir(index,0700)==0); g=(Guard){0,0}; CHECK(!WUEmojiAtomicCommit(directory,uuid,old,strlen(old),valid,&g)); CHECK(rmdir(index)==0);
    g=(Guard){0,0}; CHECK(WUEmojiAtomicCommit(directory,uuid,old,strlen(old),valid,&g)); read_equal(index,old); read_equal(source,next);
    CHECK(unlink(index)==0); CHECK(rmdir(directory)==0); CHECK(unlink(source)==0); CHECK(rmdir(root)==0);
    printf("PASS production EmoticonLibrarySafety: %d checks (atomic commit/generation/symlink/hardlink/source protection)\n",checks);
    return 0;
}
