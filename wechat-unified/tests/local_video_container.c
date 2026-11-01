#include "LocalVideoContainer.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned checks;
#define CHECK(x) do { checks++; assert(x); } while(0)
static void u32(uint8_t *p,uint32_t n) { p[0]=n>>24;p[1]=n>>16;p[2]=n>>8;p[3]=n; }
static size_t wrap(uint8_t *out,const char *type,const uint8_t *body,size_t n) { u32(out,(uint32_t)n+8); memcpy(out+4,type,4); memcpy(out+8,body,n); return n+8; }
static size_t sample(uint8_t *out) {
    uint8_t p[256]={0},q[256]={0}; u32(p+4,1); u32(p+8,12); memcpy(p+12,"url ",4); u32(p+16,1);
    size_t n=wrap(q,"dref",p,20); n=wrap(p,"dinf",q,n); n=wrap(q,"minf",p,n); n=wrap(p,"mdia",q,n); n=wrap(q,"trak",p,n); n=wrap(p,"moov",q,n);
    uint8_t brand[8]={'i','s','o','m',0,0,0,0}; size_t off=wrap(out,"ftyp",brand,8); memcpy(out+off,p,n); off+=n;
    uint8_t media=0; off+=wrap(out+off,"mdat",&media,1); return off;
}
int main(void) {
    uint8_t data[512]={0},bad[512]; size_t n=sample(data);
    CHECK(WULocalVideoContainer(data,n)); CHECK(!WULocalVideoContainer(NULL,n));
    for(size_t i=0;i<n;i++) CHECK(!WULocalVideoContainer(data,i));
    CHECK(!WULocalVideoContainer(data,64u*1024u*1024u+1));
    memcpy(bad,data,n); bad[0]=255; CHECK(!WULocalVideoContainer(bad,n));
    memcpy(bad,data,n); memcpy(bad+8,"evil",4); CHECK(!WULocalVideoContainer(bad,n));
    memcpy(bad,data,n); memcpy(bad+20,"moof",4); CHECK(!WULocalVideoContainer(bad,n));
    memcpy(bad,data,n); memcpy(bad+28,"rmra",4); CHECK(!WULocalVideoContainer(bad,n));
    // dref's url flags must be self-contained; external references never play.
    memcpy(bad,data,n); bad[n-10]=0; CHECK(!WULocalVideoContainer(bad,n));
    memcpy(bad,data,n); memcpy(bad+n-17,"urn ",4); CHECK(!WULocalVideoContainer(bad,n));
    // Extended length overflow/truncation and extra trailing data.
    memcpy(bad,data,n); u32(bad,1); memset(bad+8,255,8); CHECK(!WULocalVideoContainer(bad,n));
    memcpy(bad,data,n); bad[n]=0; CHECK(!WULocalVideoContainer(bad,n+1));
    unsigned refs=0; CHECK(!WUVideoBoxes(data,n,9,&refs));
    // Mutate all top-level lengths; bounded traversal must terminate without over-read.
    for(uint32_t i=0;i<1024;i++) { memcpy(bad,data,n); u32(bad,i); (void)WULocalVideoContainer(bad,n); checks++; }
    printf("Local video production parser: %u assertions/checks passed\n",checks);
    return 0;
}
