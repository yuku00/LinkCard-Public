#include "VoiceGeometry.h"
#include <assert.h>
#include <stdio.h>
static int intersects(WUVoiceRect a,WUVoiceRect b) {
    return a.x < b.x+b.w && a.x+a.w > b.x && a.y < b.y+b.h && a.y+a.h > b.y;
}
int main(void) {
    WUVoiceRect b={10,10,120,40}, out;
    WUVoiceRect host[]={{20,20,28,14},{85,18,22,16}};
    assert(WUVoicePlace(b,host,2,&out));
    assert(out.x>=b.x && out.y>=b.y && out.x+out.w<=b.x+b.w && out.y+out.h<=b.y+b.h);
    for(int i=0;i<2;i++) { WUVoiceRect padded={host[i].x-2,host[i].y-2,host[i].w+4,host[i].h+4}; assert(!intersects(out,padded)); }
    WUVoiceRect covered[]={{10,10,120,40}};
    assert(!WUVoicePlace(b,covered,1,&out));
    WUVoiceRect small={0,0,35,40}; assert(!WUVoicePlace(small,host,2,&out));
    WUVoiceRect bad[]={{NAN,0,2,2}}; assert(!WUVoicePlace(b,bad,1,&out));
    assert(!WUVoicePlace(b,host,129,&out));
    WUVoiceRect side[]={{10,30,55,20}};
    assert(WUVoicePlace(b,side,1,&out)); assert(!intersects(out,side[0]));
    puts("PASS: production voice safe placement, collisions and fallbacks");
    return 0;
}
