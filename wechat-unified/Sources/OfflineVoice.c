#include "OfflineVoice.h"
#include "SKP_Silk_SDK_API.h"
#include "sp_dec.h"
#include "amrdecode.h"
#include <stdlib.h>
#include <string.h>
// File <=8 MiB; packet <=5120 bytes; <=9000 20ms frames; PCM <=11.52 MB.
int WUOfflineDecode(const uint8_t *p, size_t len, WUVoiceCancel cancel, void *ctx, WUOfflinePCM *out) {
    if(!out) return 1;
    memset(out,0,sizeof(*out));
    if(!p || len>8*1024*1024 || len<6) return 1;
    size_t pos=0; int silk=0;
    if(len>=9 && !memcmp(p,"#!SILK_V3",9)) { silk=1; pos=9; }
    else if(len>=10 && p[0]==2 && !memcmp(p+1,"#!SILK_V3",9)) { silk=1; pos=10; }
    else if(!memcmp(p,"#!AMR\n",6)) pos=6;
    else return 1;
    unsigned rate=silk?16000:8000; size_t limit=rate*180u, frames=0, capacity=0, packets=0;
    float *pcm=NULL; void *state=NULL; int error=1;
    SKP_SILK_SDK_DecControlStruct control={0}; control.API_sampleRate=16000;
    if(silk) {
        SKP_int32 size=0;
        if(SKP_Silk_SDK_Get_Decoder_Size(&size) || size<=0 || size>1024*1024) goto done;
        state=calloc(1,(size_t)size);
        if(!state || SKP_Silk_SDK_InitDecoder(state)) goto done;
    } else if(GSMInitDecode(&state,(int8 *)"WU") || !state) goto done;
    while(pos<len) {
        if(cancel && cancel(ctx)) { error=2; goto done; }
        size_t bytes=0; unsigned type=0;
        if(silk) {
            if(len-pos<2) goto done;
            unsigned word=p[pos]|((unsigned)p[pos+1]<<8); pos+=2;
            // Standard SDK's optional -1 EOF marker must be the final bytes.
            if(word==65535) { if(pos!=len) goto done; break; }
            if(!word || word>5120 || word>len-pos) goto done;
            bytes=word;
        } else {
            uint8_t toc=p[pos++]; type=(toc>>3)&15;
            static const unsigned sizes[9]={12,13,15,17,19,20,26,31,5};
            // Reject reserved/padding/F bits, bad-quality frames and reserved FT.
            // SID is valid; NO_DATA/PLC is intentionally not fabricated as audio.
            if((toc&0x83) || !(toc&4) || type>8) goto done;
            bytes=sizes[type]; if(bytes>len-pos) goto done;
        }
        if(++packets>9000) goto done;
        unsigned internal=0;
        do {
            int16_t samples[960]; SKP_int16 n=0;
            if(silk) {
                if(++internal>5 || SKP_Silk_SDK_Decode(state,&control,0,p+pos,(SKP_int)bytes,samples,&n)) goto done;
                if(n!=320 || control.API_sampleRate!=16000) goto done;
            } else {
                int used=AMRDecode(state,(enum Frame_Type_3GPP)type,(UWord8 *)(p+pos),samples,MIME_IETF);
                if(used!=(int)bytes) goto done;
                n=160;
            }
            if(frames+(size_t)n>limit) goto done;
            if(frames+(size_t)n>capacity) {
                size_t next=capacity?capacity*2:rate; if(next>limit) next=limit;
                float *grown=realloc(pcm,next*sizeof(float)); if(!grown) goto done;
                pcm=grown; capacity=next;
            }
            for(int i=0;i<n;i++) pcm[frames++]=samples[i]/32768.0f;
        } while(silk && control.moreInternalDecoderFrames);
        pos+=bytes;
    }
    if(!frames || (cancel && cancel(ctx))) { error=2; goto done; }
    out->samples=pcm; out->frames=frames; out->rate=rate; pcm=NULL; error=0;
done:
    free(pcm);
    if(silk) free(state); else if(state) GSMDecodeFrameExit(&state);
    return error;
}
