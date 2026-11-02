#ifndef WCM_RECYCLE_COPY_H
#define WCM_RECYCLE_COPY_H
/* Both descriptors refer to already opened directories. No source is ever modified.
   On failure an incomplete directory may remain, without a committed manifest. */
typedef int (*WCMCancel)(void *context);
int WCMRecycleCopy(int sourceRootFD, int recycleRootFD, const char *identifier,
                   const char *transaction, WCMCancel cancelled, void *context);
/* transactionDir must be a single .incomplete-* name under the already-open
   private recycle root; manifest verification checks the exact v1 schema. */
int WCMRecycleInspect(int recycleRootFD, const char *transactionDir,
                      char *identifier, unsigned long identifierCapacity);
int WCMRecycleRestore(int recycleRootFD, int destinationRootFD,
                      const char *transactionDir, WCMCancel cancelled, void *context);
int WCMRecycleRemove(int recycleRootFD, const char *transactionDir);
#endif
