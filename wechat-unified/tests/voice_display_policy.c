#include "VoiceDisplayPolicy.h"
#include <assert.h>
#include <stdio.h>
/* Hostmock calls the actual production projection policy, not a copied decision. */
typedef struct {
    uint32_t stored, database;
    double pcm, width;
    WUVoiceDisplayIdentity lease, now;
    bool enabled, mainThread, scoped;
} Host;
static unsigned duration(Host *h, bool receiver) {
    return WUVoiceDisplayProject(h->stored,h->pcm,h->lease,h->now,
        h->enabled,h->mainThread,h->scoped,receiver);
}
static void layout(Host *h) {
    h->scoped=true;
    h->width=48+duration(h,true)/1000.0; /* Mock host's own sizing, never production width. */
    h->scoped=false;
}
int main(void) {
    const double bad[]={0,-1,NAN,INFINITY,180000.01};
    for(unsigned i=0;i<sizeof(bad)/sizeof(*bad);i++) assert(!WUVoiceDisplayMS(bad[i]));
    assert(WUVoiceDisplayMS(.1)==1 && WUVoiceDisplayMS(999.99)==999);
    assert(WUVoiceDisplayMS(1000)==1000 && WUVoiceDisplayMS(1001.9)==1001);
    assert(WUVoiceDisplayMS(59999.9)==59999 && WUVoiceDisplayMS(60000)==60000);
    assert(WUVoiceDisplayMS(60001)==60000 && WUVoiceDisplayMS(180000)==60000);
    Host h={.stored=9000,.database=9000,.pcm=2500,.lease={1,2,3,4,5},.now={1,2,3,4,5},.enabled=true,.mainThread=true};
    assert(duration(&h,true)==9000); layout(&h); assert(h.width==50.5);
    assert(h.stored==9000 && h.database==9000 && duration(&h,true)==9000);
    h.scoped=true; assert(duration(&h,false)==9000); h.scoped=false;
    h.enabled=false; layout(&h); assert(h.width==57);
    h.enabled=true; h.stored=12000; layout(&h); assert(h.width==50.5);
    h.enabled=false; layout(&h); assert(h.width==60); /* Latest host value, not saved 9s. */
    h.enabled=true;
    h.now.request++; layout(&h); assert(h.width==60); /* Same message, older async result. */
    h.now=h.lease; h.now.version++; layout(&h); assert(h.width==60);
    h.now=h.lease; h.now.generation++; layout(&h); assert(h.width==60);
    h.now=h.lease; h.now.model++; layout(&h); assert(h.width==60);
    h.now=h.lease; h.now.message++; layout(&h); assert(h.width==60);
    h.now=h.lease; h.mainThread=false; layout(&h); assert(h.width==60);
    h.mainThread=true; h.pcm=NAN; layout(&h); assert(h.width==60);
    puts("PASS: production portable display policy / units / lease / stale completion / reuse / off / latest host / invalid fallback");
    return 0;
}
