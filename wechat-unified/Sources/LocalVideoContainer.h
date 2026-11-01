#ifndef WU_LOCAL_VIDEO_CONTAINER_H
#define WU_LOCAL_VIDEO_CONTAINER_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>
// Bounded local MP4/QuickTime envelope check, NOT a codec/decode guarantee.
// Require self-contained data references; never hand reference movies to AVPlayer.
static inline uint32_t WUVideoU32(const uint8_t *p) {
    return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
}
static inline int WUVideoBoxes(const uint8_t *p, size_t n, unsigned depth, unsigned *refs) {
    if(depth>8) return 0;
    size_t i=0;
    while(i<n) {
        if(n-i<8) return 0;
        uint64_t size=WUVideoU32(p+i); size_t header=8;
        if(size==1) { if(n-i<16) return 0; size=((uint64_t)WUVideoU32(p+i+8)<<32)|WUVideoU32(p+i+12); header=16; }
        if(!size) size=n-i;
        if(size<header || size>n-i) return 0;
        const uint8_t *type=p+i+4,*body=p+i+header; size_t len=(size_t)size-header;
        if(!memcmp(type,"rmra",4) || !memcmp(type,"rdrf",4)) return 0;
        if(!memcmp(type,"dref",4)) {
            if(len<8 || WUVideoU32(body)!=0) return 0;
            uint32_t count=WUVideoU32(body+4); if(!count || count>64) return 0;
            size_t at=8;
            for(uint32_t j=0;j<count;j++) {
                // The only accepted reference is a self-contained url box.
                if(len-at<12 || WUVideoU32(body+at)!=12 || memcmp(body+at+4,"url ",4) || WUVideoU32(body+at+8)!=1) return 0;
                at+=12;
            }
            if(at!=len) return 0;
            *refs+=count;
        } else if(!memcmp(type,"moov",4) || !memcmp(type,"trak",4) || !memcmp(type,"mdia",4) || !memcmp(type,"minf",4) || !memcmp(type,"dinf",4)) {
            if(!WUVideoBoxes(body,len,depth+1,refs)) return 0;
        }
        i+=(size_t)size;
    }
    return i==n;
}
static inline int WULocalVideoContainer(const void *bytes, size_t n) {
    if(!bytes || n<40 || n>64u*1024u*1024u) return 0;
    const uint8_t *p=(const uint8_t *)bytes; size_t i=0; unsigned ftyp=0,moov=0,mdat=0,refs=0;
    while(i<n) {
        if(n-i<8) return 0;
        uint64_t size=WUVideoU32(p+i); size_t h=8;
        if(size==1) { if(n-i<16) return 0; size=((uint64_t)WUVideoU32(p+i+8)<<32)|WUVideoU32(p+i+12); h=16; }
        if(!size) size=n-i;
        if(size<h || size>n-i) return 0;
        const uint8_t *t=p+i+4;
        if(!memcmp(t,"ftyp",4)) {
            if(++ftyp!=1 || size<h+8) return 0;
            const uint8_t *brand=p+i+h;
            if(memcmp(brand,"isom",4) && memcmp(brand,"iso2",4) && memcmp(brand,"mp41",4) && memcmp(brand,"mp42",4) && memcmp(brand,"avc1",4) && memcmp(brand,"qt  ",4)) return 0;
        } else if(!memcmp(t,"moov",4)) { if(++moov!=1) return 0; }
        else if(!memcmp(t,"mdat",4)) { if(size<=h) return 0; mdat++; }
        else if(!memcmp(t,"moof",4)) return 0; // Fragmented streams need a separate verified contract.
        i+=(size_t)size;
    }
    return ftyp==1 && moov==1 && mdat>0 && WUVideoBoxes(p,n,0,&refs) && refs>0;
}
#endif
