#define _GNU_SOURCE
#include "WUBackupTar.h"
/* Fault injection only in the dedicated synthetic test executable. */
#ifdef WU_TEST_COMMIT_FAILURE
#if defined(__APPLE__)
static int wu_test_commit(int a,const char *b,int c,const char *d,unsigned int e) {
    (void)a; (void)b; (void)c; (void)d; (void)e; errno=EEXIST; return -1;
}
#define renameatx_np wu_test_commit
#else
static long wu_test_commit(long number,...) { (void)number; errno=EEXIST; return -1; }
#define syscall wu_test_commit
#endif
#endif
#include "WUStorageMigration.h"
#include "WUStorageSelection.h"
int main(int argc, char **argv) {
    (void)wu_backup_tar;
    if(argc==4 && !strcmp(argv[1],"--select-create")) {
        int docs=open(argv[2],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
        int ok=docs>=0 && wu_selection_create(docs,argv[3]);
        if(docs>=0) close(docs); return ok?0:1;
    }
    if(argc==3 && !strcmp(argv[1],"--select-open")) {
        int docs=open(argv[2],O_RDONLY|O_DIRECTORY|O_NOFOLLOW); char name[128]={0};
        int state=docs>=0?wu_selection_open(docs,name,sizeof(name)):-1;
        if(docs>=0) close(docs); if(state==1) puts(name); return state==1?0:state==0?2:1;
    }
    if(argc==4 && !strcmp(argv[1],"--diagnostic")) {
        int documents=open(argv[3],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
        if(documents<0) return 3;
        const char *reason=NULL;
        const char *support=!strcmp(argv[2],"--null")?NULL:argv[2];
        int result=wu_storage_prepare(support,documents,&reason);
        if(result>=0) { close(result); close(documents); puts("ok"); return 0; }
        printf("%s %s %d\n",wu_storage_diagnostic.stage?:"unknown",wu_storage_diagnostic.status?:"unknown",wu_storage_diagnostic.error);
        close(documents); return 1;
    }
    if(argc==4 && !strcmp(argv[1],"--verify")) {
        int source=open(argv[2],O_RDONLY|O_DIRECTORY|O_NOFOLLOW), target=open(argv[3],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
        int ok=source>=0 && target>=0 && wu_storage_tree(source,target,1,0);
        if(source>=0) close(source); if(target>=0) close(target); return ok?0:1;
    }
    if(argc==3 && !strcmp(argv[1],"--commit")) {
        int documents=open(argv[2],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
        int ok=documents>=0 && wu_storage_commit(documents);
        if(documents>=0) close(documents); return ok?0:1;
    }
    if(argc!=3) return 2;
    int documents=open(argv[2],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    const char *reason=NULL;
    int result=wu_storage_prepare(argv[1],documents,&reason);
    if(documents>=0) close(documents);
    if(result<0) { if(reason) fprintf(stderr,"%s (errno=%d: %s)\n",reason,errno,strerror(errno)); return 1; }
    close(result); return 0;
}
