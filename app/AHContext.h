#import <Foundation/Foundation.h>
#define AHContextBudget 16000
FOUNDATION_EXPORT NSDictionary *AHContextSnapshot(NSArray *messages, NSUInteger totalMessages);

FOUNDATION_EXPORT NSDictionary *AHContextWithBudget(NSArray *messages, NSUInteger totalMessages, NSUInteger budget);
