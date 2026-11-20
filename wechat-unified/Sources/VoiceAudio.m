#import "VoiceAudio.h"
#import "VoiceLogic.h"
#import "VoicePath.h"
#import "OfflineVoice.h"
#import "WUSilkEncode.h"
#include <stdlib.h>
#import <AudioToolbox/AudioToolbox.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <math.h>
#include <string.h>
NSData *WUVoiceReadLocal(NSString *path) {
    path=WUVoiceCanonicalLocalPath(path); if(!path) return nil;
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK); if(fd<0) return nil;
    struct stat st; if(fstat(fd,&st) || !S_ISREG(st.st_mode) || st.st_size<12 || st.st_size>8*1024*1024) { close(fd); return nil; }
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)st.st_size]; size_t got=0;
    while(got<data.length) { ssize_t n=read(fd,(char *)data.mutableBytes+got,data.length-got); if(n<=0) break; got+=(size_t)n; }
    struct stat after; BOOL same=!fstat(fd,&after) && after.st_size==st.st_size && after.st_mtime==st.st_mtime;
    close(fd); return got==data.length && same ? [data copy] : nil;
}
static OSStatus Read(void *ctx, SInt64 position, UInt32 count, void *out, UInt32 *actual) {
    NSData *data=(__bridge NSData *)ctx; *actual=0;
    if(position<0 || (uint64_t)position>data.length) return kAudioFilePositionError;
    *actual=(UInt32)MIN((NSUInteger)count,data.length-(NSUInteger)position);
    if(*actual) memcpy(out,(const char *)data.bytes+position,*actual); return noErr;
}
static SInt64 VoiceDataSize(void *ctx) { return (SInt64)[(__bridge NSData *)ctx length]; }
static int Cancelled(void *ctx) { return [(__bridge NSProgress *)ctx isCancelled]; }
NSDictionary *WUVoiceDecode(NSData *data) { return WUVoiceDecodeCancellable(data,nil); }
NSDictionary *WUVoiceDecodeCancellable(NSData *data, NSProgress *cancellation) {
    if(cancellation.cancelled || data.length<6 || data.length>8*1024*1024) return nil;
    const uint8_t *p=data.bytes;
    BOOL offline=(data.length>=9 && !memcmp(p,"#!SILK_V3",9)) || (data.length>=10 && p[0]==2 && !memcmp(p+1,"#!SILK_V3",9)) || !memcmp(p,"#!AMR\n",6);
    if(offline) {
        WUOfflinePCM pcm={0};
        if(WUOfflineDecode(p,data.length,Cancelled,(__bridge void *)cancellation,&pcm)) return nil;
        NSArray *peaks=WUVoicePeaks(pcm.samples,pcm.frames,1,48);
        NSDictionary *result=peaks && !cancellation.cancelled ? @{ @"duration":@(pcm.frames*1000.0/pcm.rate), @"peaks":peaks, @"sampleRate":@(pcm.rate), @"channels":@1 } : nil;
        free(pcm.samples); return result;
    }
    if(data.length<12) return nil;
    // Only known system containers reach AudioToolbox; malformed codecs fail closed.
    BOOL known=(!memcmp(p,"RIFF",4) && !memcmp(p+8,"WAVE",4)) || !memcmp(p,"caff",4) || !memcmp(p+4,"ftyp",4);
    if(!known) return nil;
    AudioFileID file=NULL; ExtAudioFileRef ext=NULL; NSDictionary *result=nil;
    if(AudioFileOpenWithCallbacks((__bridge void *)data,Read,NULL,VoiceDataSize,NULL,0,&file)) return nil;
    if(ExtAudioFileWrapAudioFileID(file,false,&ext)) { AudioFileClose(file); return nil; }
    AudioStreamBasicDescription source={0}; UInt32 size=sizeof(source);
    if(ExtAudioFileGetProperty(ext,kExtAudioFileProperty_FileDataFormat,&size,&source)) goto done;
    if(!isfinite(source.mSampleRate) || source.mSampleRate<8000 || source.mSampleRate>48000 || source.mChannelsPerFrame<1 || source.mChannelsPerFrame>2) goto done;
    {
        AudioStreamBasicDescription client={0}; client.mSampleRate=source.mSampleRate;
        client.mFormatID=kAudioFormatLinearPCM; client.mFormatFlags=kAudioFormatFlagsNativeFloatPacked;
        client.mChannelsPerFrame=source.mChannelsPerFrame; client.mBitsPerChannel=32; client.mFramesPerPacket=1;
        client.mBytesPerFrame=client.mBytesPerPacket=4*client.mChannelsPerFrame;
        if(ExtAudioFileSetProperty(ext,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client)) goto done;
        NSMutableData *pcm=[NSMutableData data]; float chunk[4096*2]; NSUInteger frames=0;
        for(;;) {
            if(cancellation.cancelled) goto done;
            UInt32 n=4096; AudioBufferList buffers={0}; buffers.mNumberBuffers=1;
            buffers.mBuffers[0].mNumberChannels=client.mChannelsPerFrame;
            buffers.mBuffers[0].mData=chunk; buffers.mBuffers[0].mDataByteSize=sizeof(chunk);
            if(ExtAudioFileRead(ext,&n,&buffers)) goto done;
            if(!n) break;
            if(n>4096 || frames+n>(NSUInteger)(source.mSampleRate*180)) goto done;
            [pcm appendBytes:chunk length:n*client.mBytesPerFrame]; frames+=n;
        }
        if(!frames) goto done;
        NSArray *peaks=WUVoicePeaks(pcm.bytes,frames,client.mChannelsPerFrame,48);
        if(peaks) result=@{@"duration":@(frames*1000.0/source.mSampleRate),@"peaks":peaks};
    }
done:
    ExtAudioFileDispose(ext); AudioFileClose(file); return result;
}

static int WUTranscodeCancelled(void *ctx) {
    BOOL (^current)(void)=(__bridge id)ctx;
    return !current || !current();
}
NSData *WUVoiceTranscodeSilk(NSData *data, BOOL (^current)(void)) {
    if(!current || !current() || data.length<12 || data.length>10*1024*1024) return nil;
    const uint8_t *p=data.bytes;
    BOOL offline=(data.length>=9 && !memcmp(p,"#!SILK_V3",9)) || (data.length>=10 && p[0]==2 && !memcmp(p+1,"#!SILK_V3",9)) || (data.length>=6 && !memcmp(p,"#!AMR\n",6));
    if(offline) {
        WUOfflinePCM decoded={0}, check={0}; WUSilkEncoded encoded={0}; NSData *result=nil;
        if(WUOfflineDecode(p,data.length,WUTranscodeCancelled,(__bridge void *)current,&decoded)) return nil;
        size_t factor=decoded.rate==8000?2:decoded.rate==16000?1:0;
        if(factor && decoded.frames && decoded.frames<=960000/factor && current()) {
            size_t count=decoded.frames*factor; int16_t *pcm=malloc(count*sizeof(*pcm));
            if(pcm) {
                for(size_t i=0;i<count;i++) { float v=decoded.samples[i/factor]; if(v>0.999969f) v=0.999969f; if(v< -1.0f) v= -1.0f; pcm[i]=(int16_t)(v*32768.0f); }
                if(!WUSilkEncode16k(pcm,count,WUTranscodeCancelled,(__bridge void *)current,&encoded) && !WUOfflineDecode(encoded.bytes,encoded.length,WUTranscodeCancelled,(__bridge void *)current,&check) && check.rate==16000 && check.frames==encoded.encoded_samples && current()) result=[NSData dataWithBytes:encoded.bytes length:encoded.length];
                free(pcm);
            }
        }
        free(decoded.samples); free(check.samples); free(encoded.bytes); return result;
    }
    if(!((!memcmp(p,"RIFF",4) && !memcmp(p+8,"WAVE",4)) || !memcmp(p,"caff",4) || !memcmp(p+4,"ftyp",4))) return nil;
    AudioFileID file=NULL; ExtAudioFileRef ext=NULL; NSData *result=nil;
    if(AudioFileOpenWithCallbacks((__bridge void *)data,Read,NULL,VoiceDataSize,NULL,0,&file)) return nil;
    if(ExtAudioFileWrapAudioFileID(file,false,&ext)) { AudioFileClose(file); return nil; }
    AudioStreamBasicDescription source={0}; UInt32 size=sizeof(source);
    if(ExtAudioFileGetProperty(ext,kExtAudioFileProperty_FileDataFormat,&size,&source)) goto done;
    if(!isfinite(source.mSampleRate) || source.mSampleRate<8000 || source.mSampleRate>48000 || source.mChannelsPerFrame<1 || source.mChannelsPerFrame>2) goto done;
    {
        AudioStreamBasicDescription client={0}; client.mSampleRate=16000; client.mFormatID=kAudioFormatLinearPCM;
        client.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked|kAudioFormatFlagsNativeEndian;
        client.mChannelsPerFrame=1; client.mBitsPerChannel=16; client.mFramesPerPacket=1; client.mBytesPerFrame=client.mBytesPerPacket=2;
        if(ExtAudioFileSetProperty(ext,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client)) goto done;
        NSMutableData *pcm=[NSMutableData data]; int16_t chunk[4096]; NSUInteger frames=0;
        for(;;) {
            if(!current()) goto done;
            UInt32 n=4096; AudioBufferList buffers={0}; buffers.mNumberBuffers=1;
            buffers.mBuffers[0].mNumberChannels=1; buffers.mBuffers[0].mData=chunk; buffers.mBuffers[0].mDataByteSize=sizeof(chunk);
            if(ExtAudioFileRead(ext,&n,&buffers)) goto done;
            if(!n) break;
            if(n>4096 || frames+n>960000) goto done;
            [pcm appendBytes:chunk length:n*2]; frames+=n;
        }
        if(!frames) goto done;
        WUSilkEncoded encoded={0};
        if(WUSilkEncode16k(pcm.bytes,frames,WUTranscodeCancelled,(__bridge void *)current,&encoded)) goto done;
        WUOfflinePCM check={0};
        if(!WUOfflineDecode(encoded.bytes,encoded.length,WUTranscodeCancelled,(__bridge void *)current,&check) && check.rate==16000 && check.frames==encoded.encoded_samples && current()) result=[NSData dataWithBytes:encoded.bytes length:encoded.length];
        free(check.samples); free(encoded.bytes);
    }
done:
    ExtAudioFileDispose(ext); AudioFileClose(file); return result;
}
