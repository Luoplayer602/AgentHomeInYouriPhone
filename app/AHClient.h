#import <Foundation/Foundation.h>
@interface AHClient : NSObject
+ (NSDictionary *)call:(NSString *)method params:(NSDictionary *)params error:(NSError **)error;
@end
