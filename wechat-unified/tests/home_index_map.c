#include "../Sources/WUHomeIndexMap.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    WUHomeIndexEntry rows[] = {
        {{0,0},{1,7},{0,4},11}, {{0,1},{1,9},{1,0},22}, {{0,2},{2,3},{1,3},33}
    };
    WUHomeIndexMap m;
    assert(WUHomeIndexMapMake(&m, rows, 3, 17));
    const WUHomeIndexEntry *e = WUHomeIndexMapFind(&m,17,WUHomeDisplayedIndex,(WUHomeIndex){0,1});
    assert(e && e->identity == 22 && WUHomeIndexEqual(e->nativeTable,(WUHomeIndex){1,9}));
    assert(WUHomeIndexMapFind(&m,17,WUHomeNativeTableIndex,(WUHomeIndex){1,9}) == e);
    assert(WUHomeIndexMapFind(&m,17,WUHomeNativeSessionIndex,(WUHomeIndex){1,0}) == e);
    assert(!WUHomeIndexMapFind(&m,18,WUHomeDisplayedIndex,(WUHomeIndex){0,1}));
    assert(!WUHomeIndexMapFind(&m,17,WUHomeDisplayedIndex,(WUHomeIndex){0,9}));
    assert(!WUHomeIndexMapFind(&m,17,(WUHomeIndexSpace)99,(WUHomeIndex){0,1}));
    WUHomeIndexEntry bad[2] = {rows[0], rows[1]};
    bad[1].displayed=bad[0].displayed; assert(!WUHomeIndexMapMake(&m,bad,2,17)); assert(!m.generation && !m.entries);
    bad[1]=rows[1]; bad[1].nativeTable=bad[0].nativeTable; assert(!WUHomeIndexMapMake(&m,bad,2,17));
    bad[1]=rows[1]; bad[1].nativeSession=bad[0].nativeSession; assert(!WUHomeIndexMapMake(&m,bad,2,17));
    bad[1]=rows[1]; bad[1].identity=bad[0].identity; assert(!WUHomeIndexMapMake(&m,bad,2,17));
    bad[1]=rows[1]; bad[1].identity=0; assert(!WUHomeIndexMapMake(&m,bad,2,17));
    bad[1]=rows[1]; bad[1].nativeSession.row=-1; assert(!WUHomeIndexMapMake(&m,bad,2,17));
    assert(!WUHomeIndexMapMake(&m,NULL,1,17));
    assert(!WUHomeIndexMapMake(&m,rows,3,0));
    assert(WUHomeIndexMapMake(&m,NULL,0,17));
    assert(!WUHomeIndexMapFind(&m,17,WUHomeDisplayedIndex,(WUHomeIndex){0,0}));
    puts("home index map: ok");
    return 0;
}
