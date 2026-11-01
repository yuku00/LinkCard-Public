#include "ThemePrimitives.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    double c[4];
    assert(WUParseRGBA("#369",c)&&fabs(c[0]-0.2)<1e-10&&c[3]==1);
    assert(WUParseRGBA("#3698",c)&&fabs(c[3]-136.0/255)<1e-10);
    assert(WUParseRGBA("#1234AB80",c)&&fabs(c[2]-171.0/255)<1e-10);
    assert(WUParseRGBA("transparent",c)&&c[0]==0&&c[3]==0);
    const char *bad[]={NULL,"","fff","#12","#12345","#1234567","#ggg","#000000ffjunk","#fff ","url(http://x)","NaN","rgba(1,2,3,1)"};
    for(size_t i=0;i<sizeof(bad)/sizeof(*bad);i++) assert(!WUParseRGBA(bad[i],c));
    for(unsigned n=0;n<256;n++) { char hex[10]; snprintf(hex,sizeof hex,"#123456%02x",n); assert(WUParseRGBA(hex,c)&&fabs(c[3]-n/255.0)<1e-10); }
    assert(WUThemeScaleScore(3,2.5)<WUThemeScaleScore(2,2.5));
    assert(WUThemeScaleScore(2,2)<WUThemeScaleScore(3,2));
    assert(WUThemeScaleScore(1,NAN)==0);
    assert(WUStyleNumber(0,0,80)&&WUStyleNumber(80,0,80));
    assert(!WUStyleNumber(81,0,80)&&!WUStyleNumber(NAN,0,80)&&!WUStyleNumber(INFINITY,0,80));
    puts("Production ThemePrimitives passed: hex/alpha exhaustive, malformed color, scale tie, finite limits (no UIKit).");
    return 0;
}
