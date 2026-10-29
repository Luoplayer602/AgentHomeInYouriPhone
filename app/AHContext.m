#import "AHContext.h"
NSDictionary *AHContextSnapshot(NSArray *messages,NSUInteger totalMessages) {
    NSMutableArray *recent=[NSMutableArray array]; NSUInteger characters=0;
    for(NSDictionary *message in messages.reverseObjectEnumerator) {
        NSUInteger length=[message[@"content"] length]; if(characters+length>AHContextBudget) break;
        [recent insertObject:message atIndex:0]; characters+=length;
    }
    return @{@"messages":recent,@"characters":@(characters),@"budget":@(AHContextBudget),@"omitted":@(MAX(totalMessages,messages.count)-recent.count)};
}
