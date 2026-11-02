#include "WUSilkEncode.h"
#include "SKP_Silk_SDK_API.h"
#include "OfflineVoice.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
static int stop(void *p) { (void)p; return 1; }
int main(void) {
    int16_t in[16001]; for (int i=0;i<16001;i++) in[i]=(int16_t)(((i%80)-40)*400);
    WUSilkEncoded o={0}; assert(WUSilkEncode16k(in,16001,NULL,NULL,&o)==0);
    assert(o.encoded_samples==16320 && o.length>10 && !memcmp(o.bytes,"\x02#!SILK_V3",10));
    SKP_int32 size=0; assert(!SKP_Silk_SDK_Get_Decoder_Size(&size));
    void *s=calloc(1,(size_t)size); assert(s && !SKP_Silk_SDK_InitDecoder(s));
    SKP_SILK_SDK_DecControlStruct c={0}; c.API_sampleRate=16000;
    size_t pos=10, frames=0, packets=0; long peak=0;
    while (pos<o.length) {
        assert(pos+2<=o.length); unsigned n=o.bytes[pos] | (o.bytes[pos+1]<<8); pos+=2;
        assert(n>0 && pos+n<=o.length); int16_t pcm[960]; SKP_int16 ns=0;
        assert(!SKP_Silk_SDK_Decode(s,&c,0,o.bytes+pos,n,pcm,&ns));
        assert(ns==320 && c.moreInternalDecoderFrames==0);
        for(int i=0;i<ns;i++) { long v=pcm[i]; if(v<0)v=-v; if(v>peak)peak=v; }
        frames+=(size_t)ns; packets++; pos+=n;
    }
    assert(frames==o.encoded_samples && packets==51 && peak>500);
    printf("synthetic: %zu packets, %zu samples, %zu bytes, peak %ld\n",packets,frames,o.length,peak);
    WUOfflinePCM existing={0}; assert(!WUOfflineDecode(o.bytes,o.length,NULL,NULL,&existing));
    assert(existing.rate==16000 && existing.frames==o.encoded_samples); free(existing.samples);
    free(s); free(o.bytes);
    memset(&o,0x55,sizeof(o)); assert(WUSilkEncode16k(in,16001,stop,NULL,&o)); assert(!o.bytes&&!o.length&&!o.encoded_samples);
    assert(WUSilkEncode16k(in,0,NULL,NULL,&o)); assert(!o.bytes);
    assert(WUSilkEncode16k(in,960001,NULL,NULL,&o)); assert(!o.bytes);
    assert(WUSilkEncode16k(NULL,10,NULL,NULL,&o)); assert(!o.bytes);
    puts("invalid input and cancellation: pass");
}
