#include "OfflineVoice.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
static unsigned checks;
#define CHECK(x) do { ++checks; assert(x); } while(0)
static unsigned char *fixture(const char *name,size_t *len) {
    char path[256]; snprintf(path,sizeof(path),"tests/fixtures/%s.hex",name);
    FILE *f=fopen(path,"r"); assert(f); unsigned char *p=malloc(10000); unsigned x; *len=0;
    while(fscanf(f,"%2x",&x)==1) { assert(*len<10000); p[(*len)++]=(unsigned char)x; } fclose(f); return p;
}
static void bad(const unsigned char *p,size_t n) {
    WUOfflinePCM out={0}; CHECK(WUOfflineDecode(p,n,NULL,NULL,&out)!=0); CHECK(!out.samples && !out.frames && !out.rate);
}
static int cancel(void *ctx) { return ++*(int *)ctx>=3; }
int main(void) {
    const char *names[]={"standard.silk","tencent.silk","synthetic.amr"};
    for(unsigned k=0;k<3;k++) {
        size_t n; unsigned char *p=fixture(names[k],&n); WUOfflinePCM out={0};
        CHECK(!WUOfflineDecode(p,n,NULL,NULL,&out)); CHECK(out.rate==(k==2?8000:16000)); CHECK(out.frames==out.rate);
        float max=0; for(size_t i=0;i<out.frames;i++) { CHECK(isfinite(out.samples[i])); if(fabsf(out.samples[i])>max) max=fabsf(out.samples[i]); }
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<out.frames;i++) { uint16_t s=(uint16_t)(int16_t)(out.samples[i]*32768.0f); hash=(hash^(s&255))*UINT64_C(1099511628211); hash=(hash^(s>>8))*UINT64_C(1099511628211); }
        fprintf(stderr,"%s: rate=%u frames=%zu peak=%g PCM-FNV64=%016llx\n",names[k],out.rate,out.frames,max,(unsigned long long)hash);
        CHECK(hash==(k==2?UINT64_C(0x66b16db954fbb6aa):UINT64_C(0xb33249e300d33e5b)));
        // Legacy GCC -O2 inflated this fixture to 9960; even -fwrapv alone is insufficient.
        // Pinned SDK at O0 / explicit wrapping yields 2992 (independent FFmpeg: 3300).
        CHECK(max==(k==2?2992.0f:12595.0f)/32768.0f); free(out.samples);
        int count=0; CHECK(WUOfflineDecode(p,n,cancel,&count,&out)==2); CHECK(!out.samples && !out.frames);
        // Appended partial frame must invalidate even otherwise fully decoded audio.
        unsigned char *tail=malloc(n+1); memcpy(tail,p,n); tail[n]=0x7c; bad(tail,n+1); free(tail);
        if(k==2) { bad(p,n-1); p[6]|=0x80; bad(p,n); p[6]&=0x7f; p[6]&=~4; bad(p,n); }
        else { size_t start=k==1?10:9; bad(p,start); p[start]=0; p[start+1]=0; bad(p,n); p[start]=1; p[start+1]=0x80; bad(p,n); }
        free(p);
    }
    bad(NULL,0); bad((const unsigned char *)"#!AMR\n",6); bad((const unsigned char *)"#!AMR-WB\n",9);
    unsigned char *large=calloc(1,8*1024*1024+1); bad(large,8*1024*1024+1); free(large);
    // Exact 180-second boundary succeeds; one further valid AMR frame fails atomically.
    size_t n; unsigned char *amr=fixture("synthetic.amr",&n); size_t len=6+9001*32;
    unsigned char *longAudio=malloc(len); memcpy(longAudio,amr,6);
    for(size_t i=0;i<9001;i++) memcpy(longAudio+6+i*32,amr+6,32);
    WUOfflinePCM out={0}; CHECK(!WUOfflineDecode(longAudio,len-32,NULL,NULL,&out)); CHECK(out.frames==8000*180); free(out.samples);
    bad(longAudio,len); free(longAudio); free(amr);
    printf("Offline production decoder: %u assertions passed (synthetic PCM, malformed input, cancellation, 180s boundary)\n",checks);
    return 0;
}
