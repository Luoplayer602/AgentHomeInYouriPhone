#import "AHContext.h"
NSDictionary *AHContextWithBudget(NSArray *messages,NSUInteger totalMessages,NSUInteger budget) {
    NSMutableArray *recent=[NSMutableArray array]; NSUInteger characters=0;
    for(NSDictionary *message in messages.reverseObjectEnumerator) {
        NSUInteger length=[message[@"content"] length]; if(characters+length>budget) break;
        [recent insertObject:message atIndex:0]; characters+=length;
    }
    return @{@"messages":recent,@"characters":@(characters),@"budget":@(budget),@"omitted":@(MAX(totalMessages,messages.count)-recent.count)};
}

NSDictionary *AHContextSnapshot(NSArray *messages,NSUInteger totalMessages) { return AHContextWithBudget(messages,totalMessages,AHContextBudget); }
