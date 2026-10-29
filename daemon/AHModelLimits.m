#import "AHModelLimits.h"
#import "../core/context/Budget.h"
#import "../app/AHProfiles.h"
#import "../app/AHProviderConfig.h"
@interface AHMetadataSession : NSObject <NSURLSessionTaskDelegate>
@end
@implementation AHMetadataSession
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler { completionHandler(nil); }
@end
static NSInteger positive(id value) { return [value respondsToSelector:@selector(integerValue)] ? MAX(0,MIN(2000000,[value integerValue])) : 0; }
NSDictionary *AHModelLimits(NSDictionary *profile) {
    static NSMutableDictionary *cache; static NSMutableDictionary *checked;
    if(!cache) { cache=[NSMutableDictionary dictionary]; checked=[NSMutableDictionary dictionary]; }
    NSString *model=[profile[@"model"] isKindOfClass:NSString.class]?profile[@"model"]:@"";
    NSString *identifier=[profile[@"id"] isKindOfClass:NSString.class]?profile[@"id"]:@"";
    NSString *error=nil; NSURL *chat=AHChatURL([profile[@"endpoint"] isKindOfClass:NSString.class]?profile[@"endpoint"]:@"",&error);
    NSString *key=[NSString stringWithFormat:@"%@|%@|%@",identifier,chat.absoluteString ?: @"",model];
    NSDictionary *found=cache[key];
    if(!found && chat) {
        static NSDictionary *catalog;
        if(!catalog) { NSData *data=[NSData dataWithContentsOfFile:@"/var/jb/usr/share/agenthome/model-limits.json"]; catalog=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:@{}; }
        NSDictionary *entry=catalog[chat.host.lowercaseString][model];
        if(entry) { NSMutableDictionary *known=[entry mutableCopy]; known[@"source"]=@"models.dev catalog 2026-10-30 (host + model ID chính xác)"; found=known; }
    }
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(chat && model.length && now-[checked[key] doubleValue]>300) {
        checked[key]=@(now);
        NSURLComponents *parts=[NSURLComponents componentsWithURL:chat resolvingAgainstBaseURL:NO];
        parts.path=[[parts.path substringToIndex:parts.path.length-@"/chat/completions".length] stringByAppendingString:@"/models"]; parts.query=nil;
        BOOL gemini=[chat.host.lowercaseString isEqual:@"generativelanguage.googleapis.com"];
        if(gemini) { parts.path=[@"/v1beta/models/" stringByAppendingString:[model hasPrefix:@"models/"]?[model substringFromIndex:7]:model]; }
        NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:parts.URL]; request.timeoutInterval=20;
        NSString *secret=AHReadKey(identifier); if(secret.length) [request setValue:[@"Bearer " stringByAppendingString:secret] forHTTPHeaderField:gemini?@"x-goog-api-key":@"Authorization"];
        if(gemini && secret.length) [request setValue:secret forHTTPHeaderField:@"x-goog-api-key"];
        AHMetadataSession *delegate=[AHMetadataSession new];
        NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration; configuration.URLCache=nil;
        NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration delegate:delegate delegateQueue:nil];
        [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *failure) {
            NSDictionary *result=nil;
            if(!failure && [(NSHTTPURLResponse *)response statusCode]==200 && data.length<=4*1024*1024) {
                id root=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                id models=[root isKindOfClass:NSDictionary.class]?root[@"data"]:nil;
                if(gemini && [root isKindOfClass:NSDictionary.class]) {
                    NSString *name=root[@"name"];
                    if([name isKindOfClass:NSString.class] && [name isEqual:[@"models/" stringByAppendingString:[model hasPrefix:@"models/"]?[model substringFromIndex:7]:model]]) {
                        NSInteger input=positive(root[@"inputTokenLimit"]), output=positive(root[@"outputTokenLimit"]);
                        if(input>=1024) result=@{@"window_tokens":@(input),@"max_input_tokens":@(input),@"model_output_tokens":@(output),@"source":@"Gemini models.get (input ceiling, conservative shared budget)",@"resolved_at":@(NSDate.date.timeIntervalSince1970)};
                    }
                }
                if([models isKindOfClass:NSArray.class]) for(id entry in models) {
                    if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"id"] isEqual:model]) continue;
                    NSDictionary *limit=[entry[@"limit"] isKindOfClass:NSDictionary.class]?entry[@"limit"]:@{};
                    NSInteger window=positive(entry[@"context_length"] ?: entry[@"context_window"] ?: entry[@"max_model_len"] ?: limit[@"context"]);
                    if(window>=1024) result=@{@"window_tokens":@(window),@"max_input_tokens":@(positive(entry[@"max_input_tokens"] ?: limit[@"input"])),@"model_output_tokens":@(positive(entry[@"max_output_tokens"] ?: limit[@"output"])),@"source":@"API /models",@"resolved_at":@(NSDate.date.timeIntervalSince1970)};
                    break;
                }
            }
            dispatch_async(dispatch_get_main_queue(),^{ if(result) cache[key]=result; });
            [session finishTasksAndInvalidate];
        }] resume];
    }
    NSMutableDictionary *result=[(found ?: @{@"window_tokens":@32768,@"source":@"Chưa biết giới hạn model; ngân sách dự phòng của app 32K"}) mutableCopy];
    NSInteger manual=positive(profile[@"context_window_tokens"]);
    if(manual) { result[@"window_tokens"]=@(MAX(1024,manual)); result[@"source"]=@"Ghi đè thủ công"; [result removeObjectForKey:@"max_input_tokens"]; }
    AHContextLimits budget=AHComputeContextLimits([result[@"window_tokens"] unsignedIntegerValue],positive(result[@"max_input_tokens"]),positive(result[@"model_output_tokens"]),positive(profile[@"max_output_tokens"]));
    result[@"output_tokens"]=@(budget.output); result[@"input_budget_tokens"]=@(budget.input); result[@"reserve_tokens"]=@(budget.reserve);
    return result;
}
