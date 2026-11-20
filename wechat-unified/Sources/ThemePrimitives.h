#ifndef WU_THEME_PRIMITIVES_H
#define WU_THEME_PRIMITIVES_H
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <ctype.h>
// CSS hex uses RRGGBBAA, not Android's AARRGGBB. XML conversion is explicit at the caller.
static inline int WUHexDigit(char c) { if(c>='0'&&c<='9') return c-'0'; c=(char)tolower((unsigned char)c); return c>='a'&&c<='f'?c-'a'+10:-1; }
static inline bool WUParseRGBA(const char *s, double rgba[4]) {
    if(!s) return false;
    if(!strcmp(s,"transparent")) { for(int i=0;i<4;i++) rgba[i]=0; return true; }
    size_t n=strlen(s); if(s[0]!='#'||(n!=4&&n!=5&&n!=7&&n!=9)) return false;
    rgba[3]=1; size_t digits=n-1, channels=(digits==3||digits==6)?3:4;
    bool shortForm=digits<5;
    for(size_t i=0;i<channels;i++) {
        int a=WUHexDigit(s[1+i*(shortForm?1:2)]),b=shortForm?a:WUHexDigit(s[2+i*2]);
        if(a<0||b<0) return false;
        rgba[i]=(a*16+b)/255.0;
    }
    return true;
}
static inline double WUThemeScaleScore(double asset, double screen) {
    if(!isfinite(screen)||screen<=0) screen=1;
    // Nearest resolution; equal distance prefers downsampling rather than upsampling.
    return fabs(asset-screen)*10+(asset<screen?1:0);
}
static inline bool WUStyleNumber(double n,double min,double max) { return isfinite(n)&&n>=min&&n<=max; }
#endif
