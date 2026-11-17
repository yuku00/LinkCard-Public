#define _GNU_SOURCE
#include "WUStorageMigration.h"
int main(int argc, char **argv) {
    (void)wu_backup_tar;
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
