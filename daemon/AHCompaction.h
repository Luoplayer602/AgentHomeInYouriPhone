#import <Foundation/Foundation.h>
#import <sqlite3.h>
@interface AHCompaction : NSObject
- (instancetype)initWithDatabase:(sqlite3 *)db;
- (void)prepareConversation:(NSString *)conversation profile:(NSDictionary *)profile task:(NSString *)task key:(NSString *)key completion:(void (^)(NSString *error))completion;
- (void)cancelPreparation:(NSString *)task;
- (id)handle:(NSString *)method params:(NSDictionary *)params error:(NSString **)error;
@end
