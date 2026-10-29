#import <Foundation/Foundation.h>
#import <sqlite3.h>
@interface AHWebServer : NSObject
- (instancetype)initWithDatabase:(sqlite3 *)db rpc:(id (^)(NSString *,NSDictionary *,NSString **))rpc;
- (id)handle:(NSString *)method params:(NSDictionary *)params error:(NSString **)error;
@end
