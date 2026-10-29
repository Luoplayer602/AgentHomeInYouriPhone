#import <Foundation/Foundation.h>
#import <sqlite3.h>
@interface AHAgentRuntime : NSObject
- (instancetype)initWithDatabase:(sqlite3 *)db tool:(NSDictionary *(^)(NSString *name))tool;
- (id)handle:(NSString *)method params:(NSDictionary *)params error:(NSString **)error;
- (void)recoverAndStart;
@end
