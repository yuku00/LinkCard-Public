#ifndef WU_HOME_INDEX_MAP_H
#define WU_HOME_INDEX_MAP_H

/* Pure index bookkeeping. This is NOT a host adapter. The caller must obtain a
 * coherent host snapshot, own storage, serialize all access/publication, and
 * invalidate the map before any host update. No host methods are called here. */
#include <stddef.h>
#include <stdint.h>

typedef struct { int64_t section, row; } WUHomeIndex;
typedef struct {
    WUHomeIndex displayed, nativeTable, nativeSession;
    uint64_t identity; /* caller-assigned nonzero token, unique in this snapshot */
} WUHomeIndexEntry;
typedef struct {
    const WUHomeIndexEntry *entries;
    size_t count;
    uint64_t generation;
} WUHomeIndexMap;

static inline int WUHomeIndexEqual(WUHomeIndex a, WUHomeIndex b) {
    return a.section == b.section && a.row == b.row;
}
static inline int WUHomeIndexValid(WUHomeIndex a) { return a.section >= 0 && a.row >= 0; }

/* Reject ambiguity rather than choosing one of two sessions. Entries and tokens
 * must remain immutable until all users of the resulting map have finished. */
static inline int WUHomeIndexMapMake(WUHomeIndexMap *out, const WUHomeIndexEntry *entries,
                                    size_t count, uint64_t generation) {
    if (!out) return 0;
    *out = (WUHomeIndexMap){0};
    if (!generation || (count && !entries)) return 0;
    for (size_t i = 0; i < count; ++i) {
        const WUHomeIndexEntry *a = &entries[i];
        if (!a->identity || !WUHomeIndexValid(a->displayed) ||
            !WUHomeIndexValid(a->nativeTable) || !WUHomeIndexValid(a->nativeSession)) return 0;
        for (size_t j = 0; j < i; ++j) {
            const WUHomeIndexEntry *b = &entries[j];
            if (a->identity == b->identity || WUHomeIndexEqual(a->displayed, b->displayed) ||
                WUHomeIndexEqual(a->nativeTable, b->nativeTable) ||
                WUHomeIndexEqual(a->nativeSession, b->nativeSession)) return 0;
        }
    }
    *out = (WUHomeIndexMap){entries, count, generation};
    return 1;
}

typedef enum { WUHomeDisplayedIndex, WUHomeNativeTableIndex, WUHomeNativeSessionIndex } WUHomeIndexSpace;
/* Caller must verify live host identity at the returned native coordinate before
 * executing an action; generation equality alone cannot detect host mutation. */
static inline const WUHomeIndexEntry *WUHomeIndexMapFind(const WUHomeIndexMap *map,
        uint64_t generation, WUHomeIndexSpace space, WUHomeIndex path) {
    if (!map || !generation || generation != map->generation || !WUHomeIndexValid(path) ||
        (map->count && !map->entries)) return NULL;
    for (size_t i = 0; i < map->count; ++i) {
        const WUHomeIndexEntry *e = &map->entries[i];
        WUHomeIndex key;
        switch (space) {
            case WUHomeDisplayedIndex: key = e->displayed; break;
            case WUHomeNativeTableIndex: key = e->nativeTable; break;
            case WUHomeNativeSessionIndex: key = e->nativeSession; break;
            default: return NULL;
        }
        if (WUHomeIndexEqual(key, path)) return e;
    }
    return NULL;
}
#endif
