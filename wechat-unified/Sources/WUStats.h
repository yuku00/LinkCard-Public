#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>
#else
@class UIViewController;
#endif

NS_ASSUME_NONNULL_BEGIN
// All binding callbacks execute on the main thread. Bind only verified host context.
// Inclusive civil dates, converted to [start midnight, day-after-end midnight)
// using calendar arithmetic (not 86400 seconds across DST). nil means invalid.
FOUNDATION_EXPORT NSDictionary * _Nullable WUStatsDateRange(NSString *start, NSString *end, NSTimeZone *zone);
FOUNDATION_EXPORT BOOL WUStatsTimeInRange(NSNumber *time, NSDictionary * _Nullable range);

@interface WUStatsBinding : NSObject
@property(nonatomic, copy, nullable) NSDictionary *dateRange;
@property(nonatomic, copy) NSTimeZone *timeZone;
// Set only when the host contract proves descending time, not from page observations.
@property(nonatomic) BOOL descendingTimeVerified;
@property(nonatomic) NSUInteger pageLimit; // 1..100, shared budget for overview
@property(nonatomic, copy, nullable) WUStatsBinding * _Nullable (^bindingForSession)(NSString *);
@property(nonatomic, copy) NSArray<NSDictionary *> *sessions;
@property(nonatomic, copy, nullable) void (^visitSnapshot)(void (^)(NSDictionary *));
@property(nonatomic, copy, nullable) void (^clearVisits)(void (^)(BOOL));
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *session;
@property(nonatomic) BOOL group;
@property(nonatomic, strong) id messageManager;
// Exact independently verified method encoding, including offsets. Empty => unavailable.
@property(nonatomic, copy) NSString *verifiedEncoding;
@property(nonatomic, copy) BOOL (^stillCurrent)(void);
// Converts a host page into normalized records and a verified next cursor.
// Return {records: NSArray, next: {id: NSNumber,time: NSNumber}, done: NSNumber}.
// Must not infer cursor semantics from array ordering. nil => reject the entire page.
@property(nonatomic, copy) NSDictionary * _Nullable (^decodePage)(NSArray *, uint32_t, NSDictionary *);
@property(nonatomic, copy) NSDictionary *initialCursor;
@end

// Normalized record: sid (server ID decimal string), lid (stable local ID decimal
// string), source, sender, time (Unix seconds), type, text. Missing/zero IDs are
// NOT unique. Same local ID across sources is NOT merged without a server ID.
// type: text/image/voice/video/emoji/link/file/location/system/pat/redpacket/transfer/other.
// Group sender must be an explicit member ID; never use room ID as sender.
FOUNDATION_EXPORT NSArray<NSString *> *WUStatsOptionalSections(void);
FOUNDATION_EXPORT NSArray<NSString *> *WUStatsSectionOrder(id _Nullable stored);
FOUNDATION_EXPORT NSArray<NSDictionary *> *WUStatsMyGroupRanking(NSArray<NSDictionary *> *rows);
// Input is the accumulator's validated, deduplicated, date-filtered normalized records.
FOUNDATION_EXPORT NSDictionary *WUStatsDetails(NSArray<NSDictionary *> *records, NSString *account, NSString *peer, BOOL group, NSTimeZone *zone);

@interface WUStatsAccumulator : NSObject
- (instancetype)initWithTimeZone:(NSTimeZone *)zone group:(BOOL)group;
- (BOOL)addRecords:(NSArray<NSDictionary *> *)records; // NO on malformed record
- (NSDictionary *)result;
@end

@interface WUStatsJob : NSObject
@property(nonatomic, readonly) BOOL cancelled;
- (instancetype)initWithBinding:(WUStatsBinding *)binding;
- (void)start:(void (^)(NSDictionary * _Nullable result, NSString *status))update;
- (void)cancel; // main thread; drops data and rejects pending callbacks
@end

@interface WUStatsOverviewJob : NSObject
@property(nonatomic, readonly) BOOL cancelled;
- (instancetype)initWithBinding:(WUStatsBinding *)binding;
- (void)start:(void (^)(NSDictionary * _Nullable, NSString *))update;
- (void)cancel;
@end

// Called on a serial IO queue. Files contain only hashed account/session IDs,
// event time and verified kind; never message text or plaintext account IDs.
FOUNDATION_EXPORT NSArray<NSDictionary *> *WUStatsVisitRanking(NSArray<NSDictionary *> *events, NSDictionary * _Nullable range);
FOUNDATION_EXPORT NSString *WUStatsVisitID(NSString *account, NSString *session);
@interface WUStatsVisitStore : NSObject
@property(nonatomic, copy, nullable) BOOL (^writeData)(NSData *, NSURL *);
- (instancetype)initWithDirectory:(NSURL *)directory account:(NSString *)account;
- (BOOL)recordSession:(NSString *)session kind:(NSString *)kind time:(NSTimeInterval)time active:(BOOL)active enabled:(BOOL)enabled current:(BOOL (^)(void))current;
- (NSDictionary *)snapshot;
- (BOOL)clearIfCurrent:(BOOL (^)(void))current;
@end

// Attach per-owner, never globally reuse another account/session's binding.
FOUNDATION_EXPORT void WUStatsBindOwner(UIViewController *owner, WUStatsBinding *binding);
FOUNDATION_EXPORT void WUShowStats(UIViewController *owner);
NS_ASSUME_NONNULL_END
