#import "AHProvider.h"
#include "../core/stream/SSEDecoder.hpp"
static NSError *AHError(NSString *message) { return [NSError errorWithDomain:@"AgentHome.Provider" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
@interface AHProvider () <NSURLSessionDataDelegate> {
    agenthome::SSEDecoder _decoder;
}
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *body;
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic,strong) NSMutableString *reasoning;
@property (nonatomic, strong) NSMutableDictionary *calls;
@property (nonatomic, strong) NSError *failure;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) void (^delta)(NSString *);
@property (nonatomic, copy) void (^completion)(NSDictionary *, NSError *);
@property NSInteger status;
@property NSUInteger received;
@property BOOL sse;
@property BOOL finished;
@property BOOL doneMarker;
@property BOOL finishReason;
@property (nonatomic,copy) NSDictionary *usage;
@property (nonatomic,copy) NSString *finishCause;
@end
@implementation AHProvider
- (void)sendTo:(NSURL *)url model:(NSString *)model key:(NSString *)key messages:(NSArray *)messages tools:(NSArray *)tools streaming:(BOOL)streaming delta:(void (^)(NSString *))delta completion:(void (^)(NSDictionary *, NSError *))completion {
    self.url = url; self.key = key; self.delta = delta; self.completion = completion;
    self.body = [NSMutableData data]; self.text = [NSMutableString string]; self.calls = [NSMutableDictionary dictionary]; self.reasoning=[NSMutableString string];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url]; request.HTTPMethod = @"POST"; request.timeoutInterval = 180;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:streaming ? @"text/event-stream" : @"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    NSError *error = nil;
    NSMutableDictionary *payload=[@{@"model":model,@"messages":messages,@"stream":@(streaming),@"max_tokens":@(self.maxOutputTokens ?: 8192)} mutableCopy];
    if(tools.count) payload[@"tools"]=tools;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (error) { completion(nil, error); return; }
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForResource = 600;
    // Serial main queue keeps cancellation and UI callbacks ordered.
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    self.task = [self.session dataTaskWithRequest:request]; [self.task resume];
}
- (void)cancel { [self.task cancel]; }
- (void)fail:(NSString *)reason { self.failure = AHError(reason); [self.task cancel]; }
- (NSString *)redact:(NSString *)text {
    if (self.key.length) text = [text stringByReplacingOccurrencesOfString:self.key withString:@"[redacted]"];
    return text.length > 400 ? [text substringToIndex:400] : text;
}
- (NSString *)providerDetail:(id)body {
    id error = [body isKindOfClass:NSDictionary.class] ? body[@"error"] : nil;
    id detail = [error isKindOfClass:NSDictionary.class] ? error[@"message"] : error;
    return [detail isKindOfClass:NSString.class] ? [self redact:detail] : @"";
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // Never forward an API key to another origin or a downgraded connection.
    NSURL *next = request.URL;
    BOOL same = [next.scheme isEqual:self.url.scheme] && [next.host isEqual:self.url.host] && ((next.port == self.url.port) || [next.port isEqual:self.url.port]);
    completionHandler(same ? request : nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.status = [(NSHTTPURLResponse *)response statusCode];
    self.sse = [response.MIMEType.lowercaseString isEqual:@"text/event-stream"] && self.status >= 200 && self.status < 300;
    completionHandler(NSURLSessionResponseAllow);
}
- (void)consume:(NSString *)event {
    if (self.doneMarker || self.failure) return;
    if ([event isEqual:@"[DONE]"]) { self.doneMarker = YES; return; }
    if (!event.length) return;
    id body = [NSJSONSerialization JSONObjectWithData:[event dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![body isKindOfClass:NSDictionary.class]) { [self fail:@"SSE chứa JSON không hợp lệ."]; return; }
    if (body[@"error"]) { [self fail:[self providerDetail:body]]; return; }
    if([body[@"usage"] isKindOfClass:NSDictionary.class]) self.usage=body[@"usage"];
    id choices = body[@"choices"];
    if(!choices && self.usage) return;
    if (![choices isKindOfClass:NSArray.class]) { [self fail:@"SSE thiếu choices."]; return; }
    if (![choices count]) return; // usage-only event
    id choice = choices[0];
    id delta = [choice isKindOfClass:NSDictionary.class] ? choice[@"delta"] : nil;
    if (![delta isKindOfClass:NSDictionary.class]) { [self fail:@"SSE delta không hợp lệ."]; return; }
    if ([choice[@"finish_reason"] isKindOfClass:NSString.class]) { self.finishReason = YES; self.finishCause=choice[@"finish_reason"]; }
    id thought=delta[@"reasoning_content"] ?: delta[@"reasoning"];
    if([thought isKindOfClass:NSString.class] && [thought length]) {
        if(self.reasoning.length+[thought length]>64000) { [self fail:@"Reasoning vượt giới hạn 64.000 ký tự."]; return; }
        [self.reasoning appendString:thought]; if(self.reasoningDelta) self.reasoningDelta(thought);
    }
    id content = delta[@"content"];
    if ([content isKindOfClass:NSString.class]) {
        if (self.text.length + [content length] > 64000) { [self fail:@"Câu trả lời vượt giới hạn 64.000 ký tự."]; return; }
        [self.text appendString:content]; if (self.delta) self.delta(content);
    }
    id calls = delta[@"tool_calls"];
    if (!calls || calls == NSNull.null) return;
    if (![calls isKindOfClass:NSArray.class]) { [self fail:@"Tool delta không hợp lệ."]; return; }
    for (id item in calls) {
        id index = [item isKindOfClass:NSDictionary.class] ? item[@"index"] : nil;
        if (![index isKindOfClass:NSNumber.class] || [index integerValue] < 0 || [index integerValue] >= 4) { [self fail:@"Tool index không hợp lệ."]; return; }
        NSMutableDictionary *call = self.calls[index];
        if (!call) { call = [@{@"id":[NSMutableString string], @"type":@"function", @"function":[@{@"name":[NSMutableString string], @"arguments":[NSMutableString string]} mutableCopy]} mutableCopy]; self.calls[index] = call; }
        // Gemini's OpenAI compatibility endpoint may attach a thought signature
        // to a function call. Preserve it when echoing the call into context.
        if ([item[@"extra_content"] isKindOfClass:NSDictionary.class]) call[@"extra_content"] = item[@"extra_content"];
        id function = item[@"function"];
        if (function && ![function isKindOfClass:NSDictionary.class]) { [self fail:@"Tool function không hợp lệ."]; return; }
        NSArray *parts = @[item[@"id"] ?: NSNull.null, function[@"name"] ?: NSNull.null, function[@"arguments"] ?: NSNull.null];
        NSArray *targets = @[call[@"id"], call[@"function"][@"name"], call[@"function"][@"arguments"]];
        for (NSUInteger i = 0; i < parts.count; i++) {
            id part = parts[i]; if (part == NSNull.null) continue;
            if (![part isKindOfClass:NSString.class] || [targets[i] length] + [part length] > 16000) { [self fail:@"Tool fragment vượt giới hạn hoặc sai kiểu."]; return; }
            [targets[i] appendString:part];
        }
    }
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (self.finished || self.failure) return;
    self.received += data.length;
    if (self.received > 2 * 1024 * 1024) { [self fail:@"Phản hồi vượt giới hạn 2 MB."]; return; }
    if (!self.sse) { [self.body appendData:data]; return; }
    try {
        auto events = _decoder.feed((const char *)data.bytes, data.length);
        for (const auto& event : events) {
            NSString *text = [[NSString alloc] initWithBytes:event.data() length:event.size() encoding:NSUTF8StringEncoding];
            if (!text) { [self fail:@"SSE không phải UTF-8 hợp lệ."]; break; }
            [self consume:text];
        }
    } catch (const std::exception&) { [self fail:@"SSE event vượt giới hạn kích thước."]; }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (self.finished) return; self.finished = YES;
    NSError *failure = self.failure ?: error;
    NSDictionary *message = nil;
    if (!failure && self.sse) {
        if (!self.doneMarker && !self.finishReason) failure = AHError(@"Luồng phản hồi bị ngắt trước khi hoàn tất.");
        else {
            NSMutableDictionary *assembled = [@{@"role":@"assistant", @"content":[self.text copy]} mutableCopy];
            if(self.reasoning.length) assembled[@"reasoning_content"]=[self.reasoning copy];
            if (self.calls.count) {
                NSMutableArray *calls = [NSMutableArray array];
                for (NSNumber *index in [self.calls.allKeys sortedArrayUsingSelector:@selector(compare:)]) [calls addObject:self.calls[index]];
                assembled[@"tool_calls"] = calls;
            }
            message = assembled;
        }
    } else if (!failure) {
        id body = [NSJSONSerialization JSONObjectWithData:self.body options:0 error:nil];
        if([body isKindOfClass:NSDictionary.class] && [body[@"usage"] isKindOfClass:NSDictionary.class]) self.usage=body[@"usage"];
        if (self.status < 200 || self.status >= 300) {
            NSString *hint = self.status == 404 ? @"Kiểm tra đường dẫn API và model ID." : @"Kiểm tra cấu hình provider; có thể tắt Streaming trong API để thử.";
            failure = AHError([NSString stringWithFormat:@"HTTP %ld\n%@%@\n%@\n%@", (long)self.status, self.url.host, self.url.path, hint, [self providerDetail:body]]);
        } else {
            id choices = [body isKindOfClass:NSDictionary.class] ? body[@"choices"] : nil;
            id value = [choices isKindOfClass:NSArray.class] && [choices count] && [choices[0] isKindOfClass:NSDictionary.class] ? choices[0][@"message"] : nil;
            if ([value isKindOfClass:NSDictionary.class]) { message = value;
                if([choices[0][@"finish_reason"] isKindOfClass:NSString.class]) self.finishCause=choices[0][@"finish_reason"];
            }
            else failure = AHError(@"Provider không trả choices[].message của Chat Completions.");
        }
    }
    if(!failure && [self.finishCause isEqual:@"length"]) failure=AHError(@"Provider đã chạm giới hạn token đầu ra; câu trả lời chưa hoàn tất. Có thể yêu cầu tiếp tục.");
    if(!failure && [self.finishCause isEqual:@"content_filter"]) failure=AHError(@"Provider đã dừng câu trả lời bằng bộ lọc nội dung.");
    void (^completion)(NSDictionary *, NSError *) = self.completion;
    self.completion = nil; self.delta = nil; self.reasoningDelta=nil; self.key = nil;
    [self.session finishTasksAndInvalidate]; self.session = nil; self.task = nil;
    if (completion) completion(message, failure);
}
@end
