#include "../Sources/WUDiagnosticRing.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    WUDiagnosticRing r={0};
    WUDiagnosticRingAdd(&r,(WUDiagnosticEvent)0);
    WUDiagnosticRingAdd(&r,(WUDiagnosticEvent)WUDiagEventEnd);
    assert(r.count==0);
    for(int i=0;i<200;i++) WUDiagnosticRingAdd(&r, i%2?WUDiagEntryManual:WUDiagEntrySelected);
    assert(r.count==WU_DIAGNOSTIC_CAPACITY && r.start==72);
    for(size_t i=0;i<r.count;i++) assert(r.values[(r.start+i)%WU_DIAGNOSTIC_CAPACITY]==(i%2?WUDiagEntryManual:WUDiagEntrySelected));
    WUDiagnosticRingAdd(&r,(WUDiagnosticEvent)999);
    assert(r.count==WU_DIAGNOSTIC_CAPACITY && r.start==72);
    WUDiagnosticRate rate={0};
    assert(WUDiagnosticRateAllow(&rate,0.0));
    assert(!WUDiagnosticRateAllow(&rate,4.999));
    assert(WUDiagnosticRateAllow(&rate,5.0));
    assert(!WUDiagnosticRateAllow(&rate,9.9));
    assert(WUDiagnosticRateAllow(&rate,1.0));
    WUDiagnosticRingAdd(&r,WUDiagAccountNameInvalid);
    assert(r.values[(r.start+r.count-1)%WU_DIAGNOSTIC_CAPACITY]==WUDiagAccountNameInvalid);
    puts("diagnostic ring: OK");
    return 0;
}
