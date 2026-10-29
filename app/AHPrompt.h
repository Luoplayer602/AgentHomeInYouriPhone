#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSDictionary *AHSystemInfoTool(void);
FOUNDATION_EXPORT NSMutableArray *AHPromptContext(NSArray *history, NSString *summary, NSString *model);
FOUNDATION_EXPORT NSDictionary *AHPromptPlan(NSArray *history, NSString *summary, NSString *model, NSUInteger inputBudget);
FOUNDATION_EXPORT NSArray *AHTools(void);
