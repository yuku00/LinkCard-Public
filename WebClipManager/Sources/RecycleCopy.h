#ifndef WCM_RECYCLE_COPY_H
#define WCM_RECYCLE_COPY_H
/* Both descriptors refer to already opened directories. No source is ever modified.
   On failure an incomplete directory may remain, without a committed manifest. */
typedef int (*WCMCancel)(void *context);
int WCMRecycleCopy(int sourceRootFD, int recycleRootFD, const char *identifier,
                   const char *transaction, WCMCancel cancelled, void *context);
#endif
