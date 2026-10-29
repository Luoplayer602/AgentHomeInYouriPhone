#import <Foundation/Foundation.h>
#import <sqlite3.h>
FOUNDATION_EXPORT NSString *AHCompactInstruction(NSUInteger summaryTokens);
FOUNDATION_EXPORT NSDictionary *AHCompactPlan(sqlite3 *db, NSString *conversation, NSString *end, NSString *summary, NSUInteger inputTokens, NSUInteger summaryTokens);
FOUNDATION_EXPORT BOOL AHCompactSummaryValid(NSString *summary, NSUInteger budget, NSUInteger beforeTokens);
FOUNDATION_EXPORT NSArray *AHCompactMissingIdentifiers(NSString *summary, NSArray *identifiers);
