#import <Foundation/Foundation.h>
#import "../Shared/FLPreferences.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        assert(!FLHasBadge(nil));
        assert(!FLHasBadge(@0));
        assert(!FLHasBadge(@(-1)));
        assert(!FLHasBadge(@(NAN)));
        assert(FLHasBadge(@3));
        assert(!FLHasBadge(@"  "));
        assert(!FLHasBadge(@"0"));
        assert(!FLHasBadge(@"-2"));
        assert(FLHasBadge(@"2"));
        assert(FLHasBadge(@"99+"));
        assert(FLHasBadge(@"!"));
        assert(!FLHasBadge(@[]));
    }
    return 0;
}
