#import "AHCompaction.h"
#import "AHActivityLease.h"
#import "AHModelLimits.h"
#import "AHHistory.h"
#import "AHCompactPlan.h"
#import "../app/AHContext.h"
#import "../app/AHPrompt.h"
#import "../app/AHProvider.h"
#import "../app/AHProfiles.h"
#import "../app/AHProviderConfig.h"
#import <CommonCrypto/CommonDigest.h>
static NSString *encode(id value) { return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding]; }
@interface AHCompaction ()
@property sqlite3 *db;
@property (nonatomic,strong) AHProvider *provider;
@property (nonatomic,copy) NSString *job;
@property (nonatomic,copy) NSString *key;
@property (nonatomic,strong) AHActivityLease *lease;
@end
@implementation AHCompaction
- (NSArray *)rows:(NSString *)sql values:(NSArray *)values {
    sqlite3_stmt *s=NULL; NSMutableArray *rows=[NSMutableArray array];
    if(sqlite3_prepare_v2(self.db,sql.UTF8String,-1,&s,NULL)==SQLITE_OK) {
        for(NSUInteger i=0;i<values.count;i++) sqlite3_bind_text(s,(int)i+1,[values[i] description].UTF8String,-1,SQLITE_TRANSIENT);
        while(sqlite3_step(s)==SQLITE_ROW) { NSMutableDictionary *row=[NSMutableDictionary dictionary]; for(int i=0;i<sqlite3_column_count(s);i++) { const char *text=(const char *)sqlite3_column_text(s,i); row[@(sqlite3_column_name(s,i))]=text?@(text):@""; } [rows addObject:row]; }
    } sqlite3_finalize(s); return rows;
}
- (BOOL)sql:(NSString *)sql values:(NSArray *)values {
    sqlite3_stmt *s=NULL; int rc=sqlite3_prepare_v2(self.db,sql.UTF8String,-1,&s,NULL); if(rc==SQLITE_OK) { for(NSUInteger i=0;i<values.count;i++) sqlite3_bind_text(s,(int)i+1,[values[i] description].UTF8String,-1,SQLITE_TRANSIENT); rc=sqlite3_step(s); } sqlite3_finalize(s); return rc==SQLITE_DONE;
}
- (instancetype)initWithDatabase:(sqlite3 *)db { if((self=[super init])) { self.db=db; [self sql:@"UPDATE compactions SET state='failed',error='Daemon restarted; previous summary unchanged' WHERE state='running'" values:@[]]; } return self; }
- (NSString *)hashThrough:(NSString *)end conversation:(NSString *)conversation {
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    sqlite3_stmt *s=NULL;
    if(sqlite3_prepare_v2(self.db,"SELECT id,role,content FROM messages WHERE conversation_id=? AND id<=? ORDER BY id",-1,&s,NULL)!=SQLITE_OK) return @"";
    sqlite3_bind_text(s,1,conversation.UTF8String,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,2,end.UTF8String,-1,SQLITE_TRANSIENT);
    while(sqlite3_step(s)==SQLITE_ROW) { @autoreleasepool {
        NSDictionary *row=@{@"id":@((const char *)sqlite3_column_text(s,0)),@"role":@((const char *)sqlite3_column_text(s,1)),@"content":@((const char *)sqlite3_column_text(s,2))};
        NSData *data=[encode(row) dataUsingEncoding:NSUTF8StringEncoding]; CC_SHA256_Update(&context,data.bytes,(CC_LONG)data.length); CC_SHA256_Update(&context,"\n",1);
    } }
    sqlite3_finalize(s); unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest,&context);
    NSMutableString *hash=[NSMutableString string]; for(NSUInteger i=0;i<sizeof(digest);i++) [hash appendFormat:@"%02x",digest[i]]; return hash;
}
- (id)handle:(NSString *)method params:(NSDictionary *)params error:(NSString **)error {
    NSString *conversation=params[@"conversation_id"];
    if(![conversation isKindOfClass:NSString.class] || !conversation.length || conversation.length>80) { *error=@"Invalid conversation"; return nil; }
    NSDictionary *active=[self rows:@"SELECT * FROM compactions WHERE conversation_id=? AND state='active' ORDER BY rowid DESC LIMIT 1" values:@[conversation]].firstObject;
    NSDictionary *latest=[self rows:@"SELECT * FROM compactions WHERE conversation_id=? ORDER BY rowid DESC LIMIT 1" values:@[conversation]].firstObject;
    if([method isEqual:@"context.status"]) {
        NSArray *history=AHHistory(self.db,conversation,active[@"end_id"] ?: @"0");
        NSDictionary *profile=[params[@"profile"] isKindOfClass:NSDictionary.class]?params[@"profile"]:@{};
        NSDictionary *limits=AHModelLimits(profile);
        NSDictionary *plan=AHPromptPlan(history,active[@"summary"],profile[@"model"],[limits[@"input_budget_tokens"] unsignedIntegerValue]);
        NSDictionary *usage=[self rows:@"SELECT u.usage,a.config FROM token_usage u JOIN tasks t ON t.id=u.task_id JOIN ai_runs a ON a.task_id=t.id WHERE t.conversation_id=? ORDER BY t.rowid DESC LIMIT 1" values:@[conversation]].firstObject;
        NSDictionary *count=[self rows:@"SELECT count(*) AS n FROM messages WHERE conversation_id=? AND id>?" values:@[conversation,active[@"end_id"] ?: @"0"]].firstObject;
        NSUInteger total=(NSUInteger)MAX(0,[count[@"n"] longLongValue]);
        NSMutableDictionary *result=[limits mutableCopy]; [result addEntriesFromDictionary:plan]; [result removeObjectForKey:@"messages"];
        result[@"active"]=active ?: @{}; result[@"latest"]=latest ?: @{}; result[@"usage"]=usage ?: @{};
        result[@"budget"]=@([limits[@"input_budget_tokens"] unsignedIntegerValue]*3);
        result[@"omitted_recent"]=@(total-MIN(total,[plan[@"recent_count"] unsignedIntegerValue]));
        result[@"estimate_method"]=@"UTF-8 JSON bytes / 3 + message overhead; approximate, not a tokenizer";
        return result;
    }
    BOOL busy=[self rows:@"SELECT id FROM tasks WHERE conversation_id=? AND state IN ('queued','running')" values:@[conversation]].count>0;
    if(busy) { *error=@"Dừng/hoàn tất tác vụ trước khi compact hoặc đổi summary."; return nil; }
    NSString *identifier=params[@"id"];
    if([method isEqual:@"context.discard"]) {
        if([@[@"running",@"ready"] containsObject:latest[@"state"] ?: @""]) {
            if([latest[@"id"] isEqual:self.job]) { [self.provider cancel]; self.provider=nil; self.job=nil; self.key=nil; [self.lease end]; self.lease=nil; }
            [self sql:@"UPDATE compactions SET state='discarded' WHERE id=? AND state IN ('running','ready')" values:@[latest[@"id"]]];
        }
        return @{@"ok":@YES};
    }
    if([method isEqual:@"context.drop"]) {
        [self sql:@"UPDATE compactions SET state='discarded' WHERE conversation_id=? AND state IN ('active','ready')" values:@[conversation]];
        if([latest[@"state"] isEqual:@"running"]) { if([latest[@"id"] isEqual:self.job]) { [self.provider cancel]; self.provider=nil; self.job=nil; self.key=nil; [self.lease end]; self.lease=nil; } [self sql:@"UPDATE compactions SET state='discarded' WHERE id=?" values:@[latest[@"id"]]]; }
        return @{@"ok":@YES};
    }
    if([method isEqual:@"context.activate"]) {
        NSDictionary *candidate=[identifier isKindOfClass:NSString.class]?[self rows:@"SELECT * FROM compactions WHERE id=? AND conversation_id=? AND state='ready'" values:@[identifier,conversation]].firstObject:nil;
        if(!candidate || ![candidate[@"source_hash"] isEqual:[self hashThrough:candidate[@"end_id"] conversation:conversation]] || ![candidate[@"base_id"] isEqual:active[@"id"] ?: @""]) { *error=@"Snapshot không còn khớp nguồn/base; hãy tạo lại."; return nil; }
        BOOL ok=[self sql:@"BEGIN IMMEDIATE" values:@[]]; if(ok) ok=[self sql:@"UPDATE compactions SET state='superseded' WHERE conversation_id=? AND state='active'" values:@[conversation]];
        if(ok) ok=[self sql:@"UPDATE compactions SET state='active' WHERE id=? AND state='ready'" values:@[identifier]];
        if(ok) ok=[self sql:@"COMMIT" values:@[]]; if(!ok) { [self sql:@"ROLLBACK" values:@[]]; *error=@"Cannot activate snapshot"; return nil; } return @{@"ok":@YES};
    }
    if(![method isEqual:@"context.compact"]) { *error=@"Unknown context method"; return nil; }
    if([latest[@"state"] isEqual:@"ready"]) { *error=@"Có snapshot chờ duyệt; dùng hoặc bỏ snapshot trước khi compact tiếp."; return nil; }
    if(self.job || [latest[@"state"] isEqual:@"running"]) { *error=@"Đang compact."; return nil; }
    NSDictionary *profile=params[@"profile"]; NSString *urlError=nil; NSURL *url=[profile isKindOfClass:NSDictionary.class] && [profile[@"endpoint"] isKindOfClass:NSString.class]?AHChatURL(profile[@"endpoint"],&urlError):nil;
    if(!url || ![profile[@"id"] isKindOfClass:NSString.class] || ![profile[@"model"] isKindOfClass:NSString.class]) { *error=urlError ?: @"Invalid provider"; return nil; }
    NSString *key=AHReadKey(profile[@"id"]); if(!key.length) { *error=@"Mở khóa máy để đọc API key."; return nil; }
    NSDictionary *limits=AHModelLimits(profile);
    NSUInteger summaryBudget=MIN((NSUInteger)4096,MAX((NSUInteger)256,[limits[@"input_budget_tokens"] unsignedIntegerValue]/8));
    summaryBudget=MIN(summaryBudget,[limits[@"output_tokens"] unsignedIntegerValue]);
    NSDictionary *plan=AHCompactPlan(self.db,conversation,active[@"end_id"] ?: @"0",active[@"summary"],[limits[@"input_budget_tokens"] unsignedIntegerValue],summaryBudget);
    if(!plan) { *error=@"Chưa có phần lịch sử hoàn tất vừa ngân sách compact. Giữ ít nhất 4 tin gần nhất; kiểm tra context window của provider."; return nil; }
    NSString *end=plan[@"end_id"], *hash=[self hashThrough:end conversation:conversation];
    NSUInteger before=[plan[@"before_chars"] unsignedIntegerValue];
    if(hash.length!=64) { *error=@"Cannot verify source history"; return nil; }
    NSString *job=NSUUID.UUID.UUIDString;
    NSMutableArray *messages=[plan[@"messages"] mutableCopy];
    NSMutableDictionary *user=[messages.lastObject mutableCopy]; user[@"content"]=[user[@"content"] stringByReplacingOccurrencesOfString:key withString:@"[API KEY REDACTED]"]; messages[messages.count-1]=user;
    NSData *redacted=[NSJSONSerialization dataWithJSONObject:messages options:0 error:nil];
    if((redacted.length+2)/3+64>[limits[@"input_budget_tokens"] unsignedIntegerValue]) { *error=@"Nội dung compact vượt ngân sách sau khi che API key."; return nil; }
    BOOL ok=[self sql:@"INSERT INTO compactions(id,conversation_id,state,end_id,source_hash,base_id,summary,provider,model,before_chars) VALUES (?,?,'running',?,?,?,'',?,?,?)" values:@[job,conversation,end,hash,active[@"id"] ?: @"",profile[@"id"],profile[@"model"],@(before)]];
    if(!ok) { *error=@"Cannot save compaction job"; return nil; }
    self.lease=[AHActivityLease new]; [self.lease begin];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_SEC),dispatch_get_main_queue(),^{ if([self.job isEqual:job]) { [self.provider cancel]; self.provider=nil; self.job=nil; self.key=nil; [self.lease end]; self.lease=nil; [self sql:@"UPDATE compactions SET state='failed',error='Compact timeout' WHERE id=? AND state='running'" values:@[job]]; } });
    self.job=job; self.key=key; self.provider=[AHProvider new]; self.provider.maxOutputTokens=summaryBudget;
    [self.provider sendTo:url model:profile[@"model"] key:key messages:messages tools:@[] streaming:NO delta:nil completion:^(NSDictionary *message,NSError *failure){
        if(![self.job isEqual:job]) return;
        NSString *summary=message[@"content"]; BOOL valid=!failure && [summary isKindOfClass:NSString.class] && AHCompactSummaryValid(summary,summaryBudget,[plan[@"before_tokens"] unsignedIntegerValue]) && (!message[@"tool_calls"] || ([message[@"tool_calls"] isKindOfClass:NSArray.class] && ![message[@"tool_calls"] count]));
        if(valid) { summary=[summary stringByReplacingOccurrencesOfString:self.key withString:@"[API KEY REDACTED]"]; valid=AHCompactSummaryValid(summary,summaryBudget,[plan[@"before_tokens"] unsignedIntegerValue]); }
        if(valid) { [self sql:@"UPDATE compactions SET state='ready',summary=?,after_chars=? WHERE id=? AND state='running'" values:@[summary,@(summary.length),job]]; }
        else [self sql:@"UPDATE compactions SET state='failed',error=? WHERE id=? AND state='running'" values:@[failure.localizedDescription ?: @"Summary không hợp lệ, quá dài hoặc chưa giảm context",job]];
        self.job=nil; self.key=nil; self.provider=nil; [self.lease end]; self.lease=nil;
    }];
    return @{@"id":job};
}
@end
