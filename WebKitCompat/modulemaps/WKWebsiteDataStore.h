#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
WK_EXTERN API_AVAILABLE(ios(9.0))
@interface WKWebsiteDataStore : NSObject
+ (instancetype)defaultDataStore;
+ (instancetype)nonPersistentDataStore;
@end
NS_ASSUME_NONNULL_END
