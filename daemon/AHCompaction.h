#import <Foundation/Foundation.h>
#import <sqlite3.h>
@interface AHCompaction : NSObject
- (instancetype)initWithDatabase:(sqlite3 *)db;
- (id)handle:(NSString *)method params:(NSDictionary *)params error:(NSString **)error;
@end
