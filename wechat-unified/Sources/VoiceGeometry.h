#ifndef WU_VOICE_GEOMETRY_H
#define WU_VOICE_GEOMETRY_H
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
typedef struct { double x,y,w,h; } WUVoiceRect;
/* Search top and bottom strips inside the host bubble, reserving two points around host content. */
static inline bool WUVoicePlace(WUVoiceRect bubble,const WUVoiceRect *obstacles,size_t n,WUVoiceRect *out) {
    if(!out || n>128 || !isfinite(bubble.x) || !isfinite(bubble.y) || !isfinite(bubble.w) || !isfinite(bubble.h) || bubble.w<40 || bubble.h<24) return false;
    double left=bubble.x+4,right=bubble.x+bubble.w-4, h=10;
    WUVoiceRect best={0};
    for(int row=0;row<2;row++) {
        double y=row?bubble.y+4:bubble.y+bubble.h-h-4;
        double x=left;
        while(x<right) {
            double end=right, next=right;
            bool blocked=false;
            for(size_t i=0;i<n;i++) {
                WUVoiceRect r=obstacles[i];
                if(!isfinite(r.x)||!isfinite(r.y)||!isfinite(r.w)||!isfinite(r.h)||r.w<0||r.h<0) return false;
                if(r.y-2>=y+h || r.y+r.h+2<=y) continue;
                double a=r.x-2,b=r.x+r.w+2;
                if(b<=x || a>=right) continue;
                if(a<=x) { blocked=true; if(b<next) next=b; }
                else if(a<end) end=a;
            }
            if(blocked) { if(next<=x) return false; x=next; continue; }
            if(end-x>best.w) best=(WUVoiceRect){x,y,end-x,h};
            if(end>=right) break;
            x=end;
        }
    }
    if(best.w<32) return false;
    *out=best; return true;
}
#endif
