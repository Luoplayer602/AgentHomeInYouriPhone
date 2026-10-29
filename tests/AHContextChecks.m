#import <Foundation/Foundation.h>
#import "../shared/AHDatabase.h"
#import "../daemon/AHCompaction.h"
#import "../daemon/AHMemorySearch.h"
#import "../daemon/AHUsage.h"
@interface AHCompaction (Testing)
- (NSString *)hashThrough:(NSString *)end conversation:(NSString *)conversation;
@end
int AHContextSelfTest(void) {
    sqlite3 *db=NULL;
    @try {
        if(sqlite3_open(":memory:",&db)!=SQLITE_OK || AHMigrate(db)!=SQLITE_OK) return 1;
        if(sqlite3_exec(db,"INSERT INTO conversations(id,title) VALUES ('test','test'),('other','other'); INSERT INTO messages(conversation_id,role,content) VALUES ('test','user','Project LOTUS-482 file /tmp/report.txt; build NOT done'),('test','assistant','Read-only acknowledgement'),('test','user','Do not deploy'),('test','assistant','Still pending'),('test','user','Next step inspect endpoint'),('test','assistant','Not executed'),('test','user','Keep font 14'),('test','assistant','Noted'),('test','user','What is project ID?'),('test','assistant','Pending');",NULL,NULL,NULL)!=SQLITE_OK) return 2;
        AHCompaction *context=[[AHCompaction alloc] initWithDatabase:db];
        NSString *hash=[context hashThrough:@"6" conversation:@"test"];
        sqlite3_stmt *s=NULL;
        sqlite3_prepare_v2(db,"INSERT INTO compactions(id,conversation_id,state,end_id,source_hash,base_id,summary,provider,model,before_chars) VALUES ('one','test','ready',6,?,'','Project LOTUS-482 /tmp/report.txt. Build NOT done','p','m',9999)",-1,&s,NULL); sqlite3_bind_text(s,1,hash.UTF8String,-1,SQLITE_TRANSIENT); if(sqlite3_step(s)!=SQLITE_DONE) return 3; sqlite3_finalize(s); s=NULL;
        NSString *error=nil;
        if(![context handle:@"context.activate" params:@{@"conversation_id":@"test",@"id":@"one"} error:&error]) return 4;
        NSDictionary *found=AHMemorySearch(db,@"test",@{@"query":@"LOTUS-482"},&error);
        if(![found[@"results"] count]) return 5;
        if([AHMemorySearch(db,@"other",@{@"query":@"LOTUS-482"},&error)[@"results"] count]) return 6;
        hash=[context hashThrough:@"8" conversation:@"test"];
        sqlite3_prepare_v2(db,"INSERT INTO compactions(id,conversation_id,state,end_id,source_hash,base_id,summary,provider,model,before_chars) VALUES ('two','test','ready',8,?,'one','Project LOTUS-482; font 14','p','m',9999)",-1,&s,NULL); sqlite3_bind_text(s,1,hash.UTF8String,-1,SQLITE_TRANSIENT); if(sqlite3_step(s)!=SQLITE_DONE) return 7; sqlite3_finalize(s); s=NULL;
        if(![context handle:@"context.activate" params:@{@"conversation_id":@"test",@"id":@"two"} error:&error]) return 8;
        if(![context handle:@"context.restore" params:@{@"conversation_id":@"test",@"id":@"one"} error:&error]) return 9;
        NSDictionary *checkpoint=[context handle:@"context.checkpoint" params:@{@"conversation_id":@"test",@"id":@"one"} error:&error];
        if(![checkpoint[@"state"] isEqual:@"active"]) return 10;
        sqlite3_exec(db,"INSERT INTO tasks(id,conversation_id,tool) VALUES ('queued-test','test','chat.ai')",NULL,NULL,NULL);
        NSDictionary *profile=@{@"id":@"p",@"endpoint":@"",@"model":@"m",@"context_window_tokens":@1024};
        AHUsageRecord(db,@"queued-test",0,profile,@{@"prompt_tokens":@1500,@"completion_tokens":@10},1000);
        AHUsageRecord(db,@"queued-test",1,profile,@{@"prompt_tokens":@1700,@"completion_tokens":@20},1000);
        NSDictionary *stats=AHUsageStats(db,profile);
        if([stats[@"requests"] integerValue]!=2 || [stats[@"input_total"] integerValue]!=3200 || [stats[@"output_total"] integerValue]!=30 || [stats[@"peak_combined"] integerValue]!=1720 || [stats[@"calibration_factor"] doubleValue]<1.86) return 11;
        if([AHUsageStats(db,@{@"id":@"other",@"endpoint":@"",@"model":@"m"})[@"requests"] integerValue]) return 12;
        if([context handle:@"context.restore" params:@{@"conversation_id":@"test",@"id":@"two"} error:&error]) return 13;
        if(![context handle:@"context.configure" params:@{@"conversation_id":@"test",@"enabled":@YES,@"threshold":@80,@"auto_activate":@YES} error:&error]) return 14;
        __block NSInteger calls=0; __block NSString *preparationError=nil;
        // Empty endpoint means metadata/compact validation fails before any network request.
        [context prepareConversation:@"test" profile:profile task:@"queued-test" key:@"test-key" completion:^(NSString *failure){ calls++; preparationError=failure; }];
        if(calls!=1 || !preparationError.length) return 15;
        [context cancelPreparation:@"queued-test"]; if(calls!=1) return 16;
        AHCompaction *restarted=[[AHCompaction alloc] initWithDatabase:db];
        __block NSInteger recovered=0;
        [restarted prepareConversation:@"test" profile:profile task:@"queued-test" key:@"test-key" completion:^(NSString *failure){ if(failure.length) recovered++; }];
        if(recovered!=1) return 18;
        if(![[context handle:@"context.checkpoint" params:@{@"conversation_id":@"test",@"id":@"one"} error:&error][@"state"] isEqual:@"active"]) return 17;
        sqlite3_close(db); db=NULL;
        puts("PASS native context: search isolation/archive, checkpoints/restore, queued guard, round usage/provider isolation/calibration, auto failure callback once, old memory preserved; no API calls");
        return 0;
    } @catch(NSException *exception) { (void)exception; if(db) sqlite3_close(db); return 99; }
}
