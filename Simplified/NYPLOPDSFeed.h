@class NYPLXML;
@class ProblemDetail;

typedef NS_ENUM(NSInteger, NYPLOPDSFeedType) {
  NYPLOPDSFeedTypeInvalid,
  NYPLOPDSFeedTypeAcquisitionGrouped,
  NYPLOPDSFeedTypeAcquisitionUngrouped,
  NYPLOPDSFeedTypeNavigation
};

@interface NYPLOPDSFeed : NSObject

@property (nonatomic, readonly) NSArray *entries;
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSArray *links;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NYPLOPDSFeedType type;
@property (nonatomic, readonly) NSDate *updated;

+ (id)new NS_UNAVAILABLE;
- (id)init NS_UNAVAILABLE;

/// The handler will be called on an arbitrary thread.
+ (void)withURL:(NSURL *)URL completionHandler:(void (^)(NYPLOPDSFeed *feed, NSDictionary *error))handler
  DEPRECATED_MSG_ATTRIBUTE("Use `withURL:handler:` instead.");

/// Asynchronously create an `NYPLOPDSFeed` from feed data accessible at a given URL.
///
/// @param URL The URL from which to fetch an OPDS feed. Must not be nil.
/// @param handler A handler that will eventually be called on the main thread with
/// the result. Must not be nil.`feed` will be nil if any problem or error occurred.
/// `problemDetail` will be present if the server returned a JSON problem detail.
/// `error` will never be nil if `feed` and `problemDetail` are nil.
+ (void)withURL:(NSURL *)URL
        handler:(void (^)(NYPLOPDSFeed *feed, ProblemDetail *problemDetail, NSError *error))handler;

// designated initializer
- (instancetype)initWithXML:(NYPLXML *)feedXML;

@end
