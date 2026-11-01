#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>
#else
@class UIViewController;
#endif

NS_ASSUME_NONNULL_BEGIN
// All binding callbacks execute on the main thread. Bind only verified host context.
@interface WUStatsBinding : NSObject
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

// Attach per-owner, never globally reuse another account/session's binding.
FOUNDATION_EXPORT void WUStatsBindOwner(UIViewController *owner, WUStatsBinding *binding);
FOUNDATION_EXPORT void WUShowStats(UIViewController *owner);
NS_ASSUME_NONNULL_END
