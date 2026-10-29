#import "AHAgentRuntime.h"
#import "AHActivityLease.h"
#import "../app/AHProvider.h"
#import "../app/AHProviderConfig.h"
#import "../app/AHProfiles.h"
#import "../app/AHContext.h"
#import "../app/AHPrompt.h"
#import "../shared/AHTasks.h"
static NSString *json(id object) { return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:object options:0 error:nil] encoding:NSUTF8StringEncoding]; }
static id parse(NSString *s) { return [NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]; }
@interface AHAgentRuntime ()
@property sqlite3 *db;
@property (nonatomic,copy) NSDictionary *(^tool)(NSString *);
@property (nonatomic,strong) AHProvider *provider;
@property (nonatomic,copy) NSString *activeID;
@property (nonatomic,strong) NSMutableArray *context;
@property (nonatomic,strong) NSDictionary *config;
@property (nonatomic,strong) NSMutableString *partial;
@property NSInteger round;
@property (nonatomic,strong) NSMutableString *reasoning;
@property (nonatomic,copy) NSString *activeKey;
@property (nonatomic,strong) AHActivityLease *lease;
@property NSTimeInterval lastCheckpoint;
@end
@implementation AHAgentRuntime
- (instancetype)initWithDatabase:(sqlite3 *)db tool:(NSDictionary *(^)(NSString *))tool { if((self=[super init])) { self.db=db; self.tool=tool; } return self; }
- (BOOL)sql:(NSString *)sql values:(NSArray *)values {
    sqlite3_stmt *s=NULL; int rc=sqlite3_prepare_v2(self.db,sql.UTF8String,-1,&s,NULL);
    if(rc==SQLITE_OK) { for(NSUInteger i=0;i<values.count;i++) sqlite3_bind_text(s,(int)i+1,[values[i] description].UTF8String,-1,SQLITE_TRANSIENT); rc=sqlite3_step(s); }
    sqlite3_finalize(s); return rc==SQLITE_DONE;
}
- (NSArray *)rows:(NSString *)sql values:(NSArray *)values {
    sqlite3_stmt *s=NULL; NSMutableArray *rows=[NSMutableArray array];
    if(sqlite3_prepare_v2(self.db,sql.UTF8String,-1,&s,NULL)==SQLITE_OK) {
        for(NSUInteger i=0;i<values.count;i++) sqlite3_bind_text(s,(int)i+1,[values[i] description].UTF8String,-1,SQLITE_TRANSIENT);
        while(sqlite3_step(s)==SQLITE_ROW) { NSMutableDictionary *row=[NSMutableDictionary dictionary]; for(int i=0;i<sqlite3_column_count(s);i++) { const char *text=(const char *)sqlite3_column_text(s,i); row[@(sqlite3_column_name(s,i))]=text?@(text):@""; } [rows addObject:row]; }
    }
    sqlite3_finalize(s); return rows;
}
- (void)recoverAndStart {
    // Remote request outcome cannot be inferred after restart. Never replay it.
    [self sql:@"BEGIN IMMEDIATE" values:@[]];
    [self sql:@"INSERT INTO messages(role,content,conversation_id) SELECT 'assistant',substr(a.partial,1,63800)||char(10)||'[Daemon khởi động lại; phản hồi gián đoạn]',t.conversation_id FROM tasks t JOIN ai_runs a ON a.task_id=t.id WHERE t.tool='chat.ai' AND t.state='running' AND a.partial<>''" values:@[]];
    [self sql:@"INSERT INTO task_events(task_id,state,note) SELECT id,'failed','Daemon restarted; remote request not replayed' FROM tasks WHERE tool='chat.ai' AND state='running'" values:@[]];
    [self sql:@"UPDATE tasks SET state='failed',result='Daemon restarted; partial response kept',updated_at=CURRENT_TIMESTAMP WHERE tool='chat.ai' AND state='running'" values:@[]];
    [self sql:@"COMMIT" values:@[]];
    [self startNext];
}
- (id)handle:(NSString *)method params:(NSDictionary *)params error:(NSString **)error {
    if([method isEqual:@"ai.submit"]) {
        NSString *identifier=params[@"id"], *conversation=params[@"conversation_id"], *text=params[@"text"]; NSDictionary *config=params[@"profile"];
        if(![identifier isKindOfClass:NSString.class] || identifier.length<8 || identifier.length>80 || ![conversation isKindOfClass:NSString.class] || ![text isKindOfClass:NSString.class] || !text.length || text.length>8000 || ![config isKindOfClass:NSDictionary.class]) { *error=@"Invalid AI request"; return nil; }
        NSArray *existing=[self rows:@"SELECT id FROM tasks WHERE id=? AND conversation_id=? AND tool='chat.ai'" values:@[identifier,conversation]]; if(existing.count) return @{@"id":identifier};
        if([self rows:@"SELECT id FROM tasks WHERE conversation_id=? AND tool='chat.ai' AND state IN ('queued','running')" values:@[conversation]].count) { *error=@"Conversation already has an active AI task"; return nil; }
        if([self rows:@"SELECT id FROM compactions WHERE conversation_id=? AND state='running'" values:@[conversation]].count) { *error=@"Đang compact hội thoại; vui lòng chờ hoặc bỏ snapshot."; return nil; }
        NSString *urlError=nil; NSURL *url=[config[@"endpoint"] isKindOfClass:NSString.class]?AHChatURL(config[@"endpoint"],&urlError):nil;
        if(!url || ![config[@"id"] isKindOfClass:NSString.class] || ![config[@"model"] isKindOfClass:NSString.class] || ![config[@"model"] length]) { *error=urlError ?: @"Invalid provider"; return nil; }
        NSDictionary *snapshot=@{@"id":config[@"id"],@"endpoint":url.absoluteString,@"model":config[@"model"],@"disableStreaming":@([config[@"disableStreaming"] boolValue]),@"context_window_tokens":@([config[@"context_window_tokens"] integerValue]),@"max_output_tokens":@([config[@"max_output_tokens"] respondsToSelector:@selector(integerValue)] ? MAX(256,MIN(32768,[config[@"max_output_tokens"] integerValue])):8192)};
        BOOL ok=[self sql:@"BEGIN IMMEDIATE" values:@[]];
        if(ok) ok=[self sql:@"INSERT INTO tasks(id,conversation_id,tool) VALUES (?,?,'chat.ai')" values:@[identifier,conversation]];
        if(ok) ok=[self sql:@"INSERT INTO messages(role,content,conversation_id) VALUES ('user',?,?)" values:@[text,conversation]];
        NSDictionary *summary=[self rows:@"SELECT id,end_id,summary FROM compactions WHERE conversation_id=? AND state='active' LIMIT 1" values:@[conversation]].firstObject;
        NSArray *history=[[[self rows:@"SELECT role,content FROM messages WHERE conversation_id=? AND id>? ORDER BY id DESC LIMIT 100" values:@[conversation,summary[@"end_id"] ?: @"0"]] reverseObjectEnumerator] allObjects];
        NSMutableArray *context=AHPromptContext(history,summary[@"summary"],snapshot[@"model"]);
        if(ok) ok=[self sql:@"INSERT INTO ai_runs(task_id,config,context) VALUES (?,?,?)" values:@[identifier,json(snapshot),json(context)]];
        NSString *title=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] firstObject]; if(title.length>60) title=[title substringToIndex:60];
        if(ok) ok=[self sql:@"UPDATE conversations SET title=CASE WHEN title='Hội thoại mới' THEN ? ELSE title END,accessed_at=(julianday('now')-2440587.5)*86400 WHERE id=?" values:@[title,conversation]];
        if(ok) ok=AHTaskEvent(self.db,identifier.UTF8String,"queued","AI turn accepted; provider snapshot saved without API key")==SQLITE_OK;
        if(ok) ok=[self sql:@"COMMIT" values:@[]]; if(!ok) { [self sql:@"ROLLBACK" values:@[]]; *error=@"Cannot persist AI task"; return nil; }
        dispatch_async(dispatch_get_main_queue(),^{ [self startNext]; }); return @{@"id":identifier};
    }
    if([method isEqual:@"ai.snapshot"]) {
        NSString *conversation=params[@"conversation_id"]; if(![conversation isKindOfClass:NSString.class]) { *error=@"Invalid conversation"; return nil; }
        NSDictionary *row=[self rows:@"SELECT t.id,t.state,t.result,a.partial,a.reasoning FROM tasks t JOIN ai_runs a ON a.task_id=t.id WHERE t.conversation_id=? ORDER BY t.rowid DESC LIMIT 1" values:@[conversation]].firstObject;
        return row ?: @{};
    }
    if([method isEqual:@"ai.cancel"]) {
        NSString *identifier=params[@"id"]; if(![identifier isKindOfClass:NSString.class]) { *error=@"Invalid task"; return nil; }
        NSDictionary *task=[self rows:@"SELECT state FROM tasks WHERE id=? AND tool='chat.ai'" values:@[identifier]].firstObject;
        if([identifier isEqual:self.activeID]) { [self.provider cancel]; self.provider=nil; [self finish:@"cancelled" error:@"Đã dừng" answer:nil]; }
        else if([task[@"state"] isEqual:@"queued"]) AHTaskTransition(self.db,identifier.UTF8String,"queued","cancelled","","Cancelled before request");
        return @{@"ok":@YES};
    }
    *error=@"Unknown AI method"; return nil;
}
- (void)startNext {
    if(self.activeID) return;
    NSDictionary *run=[self rows:@"SELECT t.id,a.config,a.context,a.partial,a.round FROM tasks t JOIN ai_runs a ON a.task_id=t.id WHERE t.state='queued' ORDER BY t.rowid LIMIT 1" values:@[]].firstObject;
    if(!run) return;
    if(AHTaskTransition(self.db,[run[@"id"] UTF8String],"queued","running","","Provider request started")!=SQLITE_OK) return;
    self.activeID=run[@"id"]; self.config=parse(run[@"config"]); self.context=[parse(run[@"context"]) mutableCopy]; self.partial=[NSMutableString string]; self.round=[run[@"round"] integerValue];
    self.reasoning=[NSMutableString string];
    self.activeKey=AHReadKey(self.config[@"id"]);
    self.lease=[AHActivityLease new]; int32_t power=[self.lease begin];
    NSString *note=[NSString stringWithFormat:@"Power assertion result: %d (0=accepted); display may lock",(int)power];
    AHTaskEvent(self.db,self.activeID.UTF8String,"running",note.UTF8String);
    NSString *identifier=self.activeID;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,900*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if([self.activeID isEqual:identifier]) { [self.provider cancel]; self.provider=nil; [self finish:@"failed" error:@"Đã đạt giới hạn thời gian 15 phút cho một lượt." answer:nil]; }
    });
    [self request];
}
- (void)checkpoint {
    [self sql:@"UPDATE ai_runs SET partial=?,context=?,round=? WHERE task_id=?" values:@[self.partial,json(self.context),@(self.round),self.activeID]];
    [self sql:@"UPDATE ai_runs SET reasoning=? WHERE task_id=?" values:@[self.reasoning ?: @"",self.activeID]];
    self.lastCheckpoint=NSDate.timeIntervalSinceReferenceDate;
}
- (void)request {
    NSString *key=self.activeKey;
    if(!key.length) { [self finish:@"failed" error:@"Daemon không đọc được API key khi bắt đầu lượt. Mở khóa thiết bị rồi gửi lại." answer:nil]; return; }
    NSString *identifier=self.activeID; self.provider=[AHProvider new];
    self.provider.maxOutputTokens=[self.config[@"max_output_tokens"] unsignedIntegerValue] ?: 8192;
    __weak AHAgentRuntime *weakSelf=self;
    self.provider.reasoningDelta=^(NSString *delta){
        AHAgentRuntime *self=weakSelf; if(!self || ![self.activeID isEqual:identifier]) return; [self.reasoning appendString:delta];
        if(NSDate.timeIntervalSinceReferenceDate-self.lastCheckpoint>0.2) [self checkpoint];
    };
    NSDictionary *tool=AHSystemInfoTool();
    [self.provider sendTo:[NSURL URLWithString:self.config[@"endpoint"]] model:self.config[@"model"] key:key messages:self.context tools:@[tool] streaming:![self.config[@"disableStreaming"] boolValue] delta:^(NSString *delta){
        if(![self.activeID isEqual:identifier]) return; [self.partial appendString:delta];
        if(NSDate.timeIntervalSinceReferenceDate-self.lastCheckpoint>0.2) [self checkpoint];
    } completion:^(NSDictionary *message,NSError *error){
        if(![self.activeID isEqual:identifier]) return;
        if(self.provider.usage) [self sql:@"INSERT OR REPLACE INTO token_usage(task_id,usage) VALUES (?,?)" values:@[identifier,json(self.provider.usage)]];
        NSString *finish=[NSString stringWithFormat:@"Provider finish_reason: %@",self.provider.finishCause ?: @"not supplied"];
        AHTaskEvent(self.db,identifier.UTF8String,"running",finish.UTF8String); self.provider=nil;
        if(!self.reasoning.length && [message[@"reasoning_content"] isKindOfClass:NSString.class]) [self.reasoning appendString:[message[@"reasoning_content"] substringToIndex:MIN([message[@"reasoning_content"] length],(NSUInteger)64000)]];
        if(error) {
            if(!self.partial.length && [message[@"content"] isKindOfClass:NSString.class]) [self.partial appendString:message[@"content"]];
            [self finish:@"failed" error:error.localizedDescription answer:nil]; return;
        }
        id calls=message[@"tool_calls"];
        if([calls isKindOfClass:NSArray.class] && [calls count]) {
            if(self.round>=3 || [calls count]>4) { [self finish:@"failed" error:@"Tool limit exceeded" answer:nil]; return; }
            for(id call in calls) {
                id function=[call isKindOfClass:NSDictionary.class]?call[@"function"]:nil;
                if(![call isKindOfClass:NSDictionary.class] || ![function isKindOfClass:NSDictionary.class] || ![call[@"id"] isKindOfClass:NSString.class] || ![function[@"name"] isEqual:@"system_info"] || ![function[@"arguments"] isKindOfClass:NSString.class]) { [self finish:@"failed" error:@"Tool denied" answer:nil]; return; }
                id args=parse(function[@"arguments"]); if(![args isKindOfClass:NSDictionary.class] || [args count]) { [self finish:@"failed" error:@"Tool arguments denied" answer:nil]; return; }
            }
            [self.context addObject:message];
            for(NSDictionary *call in calls) { NSDictionary *result=self.tool(@"system.info"); [self.context addObject:@{@"role":@"tool",@"tool_call_id":call[@"id"],@"content":json(result ?: @{@"error":@"Tool failed"})}]; AHTaskEvent(self.db,identifier.UTF8String,"running","Executed system.info (risk 0)"); }
            self.round++; self.partial=[NSMutableString string]; [self checkpoint]; [self request]; return;
        }
        id answer=message[@"content"]; if(![answer isKindOfClass:NSString.class] || ![answer length]) { [self finish:@"failed" error:@"Invalid provider answer" answer:nil]; return; }
        if([answer length]>64000) { self.partial=[[answer substringToIndex:64000] mutableCopy]; [self finish:@"failed" error:@"Câu trả lời vượt giới hạn 64.000 ký tự; đã giữ phần nhận được." answer:nil]; return; }
        [self finish:@"completed" error:nil answer:answer];
    }];
}
- (void)finish:(NSString *)state error:(NSString *)error answer:(NSString *)answer {
    NSString *identifier=self.activeID;
    NSString *text=answer;
    if(!text.length && self.partial.length) text=[[self.partial substringToIndex:MIN(self.partial.length,(NSUInteger)63800)] stringByAppendingFormat:@"\n\n[%@]",error ?: state];
    if(text.length>64000) text=[text substringToIndex:64000];
    [self checkpoint];
    BOOL ok=[self sql:@"BEGIN IMMEDIATE" values:@[]];
    if(ok && text.length) ok=[self sql:@"INSERT INTO messages(role,content,conversation_id) SELECT 'assistant',?,conversation_id FROM tasks WHERE id=? AND state='running'" values:@[text,identifier]];
    if(ok) ok=[self sql:@"UPDATE tasks SET state=?,result=?,updated_at=CURRENT_TIMESTAMP WHERE id=? AND state='running'" values:@[state,error ?: @"",identifier]];
    if(ok) ok=[self sql:@"UPDATE ai_runs SET partial=? WHERE task_id=?" values:@[text ?: @"",identifier]];
    if(ok) ok=AHTaskEvent(self.db,identifier.UTF8String,state.UTF8String,(error ?: @"Assistant message committed").UTF8String)==SQLITE_OK;
    if(ok) ok=[self sql:@"COMMIT" values:@[]]; if(!ok) { [self sql:@"ROLLBACK" values:@[]];
        [self sql:@"UPDATE tasks SET state='failed',result='Could not commit assistant response' WHERE id=? AND state='running'" values:@[identifier]];
    }
    [self.lease end]; self.lease=nil; self.activeKey=nil;
    self.activeID=nil; self.context=nil; self.config=nil; self.partial=nil; self.reasoning=nil; self.provider=nil;
    dispatch_async(dispatch_get_main_queue(),^{ [self startNext]; });
}
@end
