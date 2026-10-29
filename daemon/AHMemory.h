#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSArray *AHMemorySources(NSString *prior, NSArray *recent);
FOUNDATION_EXPORT NSArray *AHMemoryRequired(NSArray *sources);
FOUNDATION_EXPORT NSString *AHMemoryCanonical(NSString *output, NSArray *sources, NSArray *required, NSString **error);
FOUNDATION_EXPORT NSString *AHMemoryPreview(NSString *memory);
FOUNDATION_EXPORT NSString *AHMemoryMinimum(NSArray *required);
