#import <Foundation/Foundation.h>
#import <sqlite3.h>
FOUNDATION_EXPORT void AHUsageRecord(sqlite3 *db,NSString *task,NSInteger round,NSDictionary *profile,NSDictionary *usage,NSUInteger estimated);
FOUNDATION_EXPORT NSDictionary *AHUsageStats(sqlite3 *db,NSDictionary *profile);
FOUNDATION_EXPORT double AHUsageFactor(sqlite3 *db,NSDictionary *profile);
