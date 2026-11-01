#import "VoiceAudio.h"
#import "VoiceLogic.h"
#import <AudioToolbox/AudioToolbox.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <math.h>
#include <string.h>
NSData *WUVoiceReadLocal(NSString *path) {
    if(![path isKindOfClass:NSString.class] || !path.isAbsolutePath) return nil;
    NSString *resolved=path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    NSString *home=[NSHomeDirectory().stringByResolvingSymlinksInPath stringByAppendingString:@"/"];
    if(![resolved hasPrefix:home] || ![resolved isEqual:path.stringByStandardizingPath]) return nil;
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
NSDictionary *WUVoiceDecode(NSData *data) {
    if(data.length<12 || data.length>8*1024*1024) return nil;
    const uint8_t *p=data.bytes;
    // SILK/AMR/raw data are deliberately not passed to an unrelated decoder.
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
