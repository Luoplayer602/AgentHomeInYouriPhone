#import <Foundation/Foundation.h>
@interface AHProvider : NSObject
@property NSUInteger maxOutputTokens;
@property (nonatomic,copy,readonly) NSDictionary *usage;
@property (nonatomic,copy) void (^reasoningDelta)(NSString *text);
@property (nonatomic,copy,readonly) NSString *finishCause;
// Callbacks run on the main thread; one instance represents one request.
- (void)sendTo:(NSURL *)url model:(NSString *)model key:(NSString *)key messages:(NSArray *)messages tools:(NSArray *)tools streaming:(BOOL)streaming delta:(void (^)(NSString *text))delta completion:(void (^)(NSDictionary *message, NSError *error))completion;
- (void)cancel;
@end
