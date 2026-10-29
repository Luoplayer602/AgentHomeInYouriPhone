#import "../shared/AHProtocol.h"
#import "AHAgentRuntime.h"
#import "AHWebServer.h"
#import "AHCompaction.h"
#import <sqlite3.h>
#import "../shared/AHDatabase.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <sys/statvfs.h>
#import <unistd.h>
#import <signal.h>
#import <errno.h>
static sqlite3 *db;
static AHAgentRuntime *agent;
static AHWebServer *web;
static AHCompaction *compaction;
static id execute(NSString *method, NSDictionary *params, NSString **error) {
    if([method hasPrefix:@"context."]) return [compaction handle:method params:params error:error];
    if([method hasPrefix:@"web."]) return [web handle:method params:params error:error];
    if([method hasPrefix:@"ai."]) return [agent handle:method params:params error:error];
    if ([method isEqual:@"system.info"]) {
        struct statvfs fs;
        if (statvfs("/var/mobile", &fs)) { *error = @"Cannot read storage"; return nil; }
        return @{@"tool": @"system.info", @"risk": @0, @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
            @"free_bytes": @((unsigned long long)fs.f_bavail * fs.f_frsize),
            @"total_bytes": @((unsigned long long)fs.f_blocks * fs.f_frsize), @"uid": @(getuid())};
    }
    if ([method isEqual:@"task.create"]) {
        NSString *conversation=params[@"conversation_id"], *tool=params[@"tool"];
        if(![conversation isKindOfClass:NSString.class] || !conversation.length || conversation.length>80 || ![tool isEqual:@"system.info"]) { *error=@"Task capability denied: only system.info is allowed"; return nil; }
        NSString *identifier=NSUUID.UUID.UUIDString;
        if(AHTaskCreate(db,identifier.UTF8String,conversation.UTF8String)!=SQLITE_OK) { *error=@"Cannot save task"; return nil; }
        return @{@"id":identifier,@"state":@"queued",@"risk":@0};
    }
    if ([method isEqual:@"task.list"]) {
        NSString *conversation=params[@"conversation_id"];
        if(![conversation isKindOfClass:NSString.class]) { *error=@"Invalid conversation"; return nil; }
        sqlite3_stmt *s=NULL;
        if(sqlite3_prepare_v2(db,"SELECT id,state,result,created_at,tool FROM tasks WHERE conversation_id=? ORDER BY rowid DESC LIMIT 50",-1,&s,NULL)!=SQLITE_OK) { *error=@"Task read failed"; return nil; }
        sqlite3_bind_text(s,1,conversation.UTF8String,-1,SQLITE_TRANSIENT);
        NSMutableArray *items=[NSMutableArray array];
        while(sqlite3_step(s)==SQLITE_ROW) [items addObject:@{@"id":@((const char *)sqlite3_column_text(s,0)),@"state":@((const char *)sqlite3_column_text(s,1)),@"result":@((const char *)sqlite3_column_text(s,2)),@"created_at":@((const char *)sqlite3_column_text(s,3)),@"tool":@((const char *)sqlite3_column_text(s,4))}];
        sqlite3_finalize(s); return @{@"tasks":items};
    }
    if ([method isEqual:@"task.events"]) {
        NSString *identifier=params[@"id"];
        if(![identifier isKindOfClass:NSString.class]) { *error=@"Invalid task ID"; return nil; }
        sqlite3_stmt *s=NULL;
        if(sqlite3_prepare_v2(db,"SELECT state,note,created_at FROM task_events WHERE task_id=? ORDER BY id LIMIT 100",-1,&s,NULL)!=SQLITE_OK) { *error=@"Event read failed"; return nil; }
        sqlite3_bind_text(s,1,identifier.UTF8String,-1,SQLITE_TRANSIENT); NSMutableArray *events=[NSMutableArray array];
        while(sqlite3_step(s)==SQLITE_ROW) [events addObject:@{@"state":@((const char *)sqlite3_column_text(s,0)),@"note":@((const char *)sqlite3_column_text(s,1)),@"at":@((const char *)sqlite3_column_text(s,2))}];
        sqlite3_finalize(s); return @{@"events":events};
    }
    if ([method isEqual:@"chat.conversations"]) {
        sqlite3_stmt *s = NULL;
        if (sqlite3_prepare_v2(db, AHConversationsSQL, -1, &s, NULL) != SQLITE_OK) { *error = @"Database read failed"; return nil; }
        NSMutableArray *items = [NSMutableArray array];
        while (sqlite3_step(s) == SQLITE_ROW) [items addObject:@{@"id":@((const char *)sqlite3_column_text(s,0)), @"title":@((const char *)sqlite3_column_text(s,1)), @"pinned":@(sqlite3_column_int(s,2)), @"accessed_at":@(sqlite3_column_double(s,3))}];
        sqlite3_finalize(s); return @{@"conversations":items};
    }
    if ([@[@"chat.touch",@"chat.pin",@"chat.delete"] containsObject:method]) {
        NSString *identifier=params[@"conversation_id"];
        if (![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length>80) { *error=@"Invalid conversation ID"; return nil; }
        BOOL deletion=[method isEqual:@"chat.delete"], pin=[method isEqual:@"chat.pin"];
        if(pin && ![params[@"pinned"] isKindOfClass:NSNumber.class]) { *error=@"Invalid pinned value"; return nil; }
        sqlite3_stmt *s=NULL; int rc=SQLITE_OK;
        if(deletion) {
            rc=sqlite3_exec(db,"BEGIN IMMEDIATE",NULL,NULL,NULL);
            if(rc==SQLITE_OK) rc=sqlite3_prepare_v2(db,"DELETE FROM messages WHERE conversation_id=?",-1,&s,NULL);
            if(rc==SQLITE_OK) { sqlite3_bind_text(s,1,identifier.UTF8String,-1,SQLITE_TRANSIENT); rc=sqlite3_step(s); }
            sqlite3_finalize(s); s=NULL;
            if(rc==SQLITE_DONE) rc=SQLITE_OK;
        }
        const char *sql=deletion ? "DELETE FROM conversations WHERE id=?" : (pin ? "UPDATE conversations SET pinned=? WHERE id=?" : "UPDATE conversations SET accessed_at=(julianday('now')-2440587.5)*86400 WHERE id=?");
        if(rc==SQLITE_OK) rc=sqlite3_prepare_v2(db,sql,-1,&s,NULL);
        if(rc==SQLITE_OK) { if(pin) sqlite3_bind_int(s,1,[params[@"pinned"] boolValue]); sqlite3_bind_text(s,pin?2:1,identifier.UTF8String,-1,SQLITE_TRANSIENT); rc=sqlite3_step(s); }
        int changed=sqlite3_changes(db); sqlite3_finalize(s);
        if(deletion) {
            if(rc==SQLITE_DONE) rc=sqlite3_exec(db,"COMMIT",NULL,NULL,NULL);
            else sqlite3_exec(db,"ROLLBACK",NULL,NULL,NULL);
        } else if(rc==SQLITE_DONE) rc=SQLITE_OK;
        if(rc!=SQLITE_OK || !changed) { *error=@"Conversation operation failed"; return nil; }
        return @{@"ok":@YES};
    }
    if ([method isEqual:@"chat.create"]) {
        NSString *identifier = NSUUID.UUID.UUIDString;
        sqlite3_stmt *s = NULL;
        int rc = sqlite3_prepare_v2(db, "INSERT INTO conversations(id,title,accessed_at) VALUES (?,'Hội thoại mới',(julianday('now')-2440587.5)*86400)", -1, &s, NULL);
        if (rc == SQLITE_OK) { sqlite3_bind_text(s,1,identifier.UTF8String,-1,SQLITE_TRANSIENT); rc = sqlite3_step(s); }
        sqlite3_finalize(s);
        if (rc != SQLITE_DONE) { *error = @"Cannot create conversation"; return nil; }
        return @{@"id":identifier, @"title":@"Hội thoại mới"};
    }
    if ([method isEqual:@"chat.list"] || [method isEqual:@"chat.append"]) {
        NSString *identifier = params[@"conversation_id"] ?: @"legacy";
        if (![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length > 80) { *error = @"Invalid conversation ID"; return nil; }
        sqlite3_stmt *s = NULL;
        int rc = sqlite3_prepare_v2(db, "SELECT 1 FROM conversations WHERE id=?", -1, &s, NULL);
        if (rc == SQLITE_OK) { sqlite3_bind_text(s,1,identifier.UTF8String,-1,SQLITE_TRANSIENT); rc = sqlite3_step(s); }
        sqlite3_finalize(s);
        if (rc != SQLITE_ROW) { *error = @"Conversation not found; restart the updated daemon if needed"; return nil; }
        if ([method isEqual:@"chat.list"]) {
            if (sqlite3_prepare_v2(db, AHMessagesSQL, -1, &s, NULL) != SQLITE_OK) { *error = @"Database read failed"; return nil; }
            sqlite3_bind_text(s,1,identifier.UTF8String,-1,SQLITE_TRANSIENT);
            NSMutableArray *items = [NSMutableArray array]; NSUInteger bytes = 0;
            while (sqlite3_step(s) == SQLITE_ROW) {
                NSDictionary *item = @{@"role":@((const char *)sqlite3_column_text(s,0)), @"content":@((const char *)sqlite3_column_text(s,1))};
                NSUInteger size = [NSJSONSerialization dataWithJSONObject:item options:0 error:nil].length + 1;
                if (bytes + size > 512 * 1024) break;
                bytes += size; [items addObject:item];
            }
            sqlite3_finalize(s);
            NSUInteger total=items.count; s=NULL;
            if(sqlite3_prepare_v2(db,"SELECT count(*) FROM messages WHERE conversation_id=?",-1,&s,NULL)==SQLITE_OK) { sqlite3_bind_text(s,1,identifier.UTF8String,-1,SQLITE_TRANSIENT); if(sqlite3_step(s)==SQLITE_ROW) total=sqlite3_column_int64(s,0); } sqlite3_finalize(s);
            return @{@"messages":[[items reverseObjectEnumerator] allObjects],@"total_messages":@(total)};
        }
        NSString *role = params[@"role"], *content = params[@"content"];
        if (![@[@"user",@"assistant"] containsObject:role] || ![content isKindOfClass:NSString.class] || !content.length || content.length > 64000) { *error = @"Invalid message"; return nil; }
        s = NULL;
        rc = sqlite3_exec(db,"BEGIN IMMEDIATE",NULL,NULL,NULL);
        if (rc == SQLITE_OK) rc = sqlite3_prepare_v2(db, AHInsertSQL, -1, &s, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_bind_text(s,1,role.UTF8String,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,2,content.UTF8String,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,3,identifier.UTF8String,-1,SQLITE_TRANSIENT); rc = sqlite3_step(s);
        }
        sqlite3_finalize(s); s = NULL;
        if (rc == SQLITE_DONE) rc = sqlite3_prepare_v2(db,"UPDATE conversations SET updated_at=strftime('%s','now'),accessed_at=(julianday('now')-2440587.5)*86400,title=CASE WHEN title='Hội thoại mới' AND ?='user' THEN ? ELSE title END WHERE id=?",-1,&s,NULL);
        if (rc == SQLITE_OK) {
            NSString *title = [[content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] firstObject];
            if (title.length > 60) title = [title substringToIndex:60];
            sqlite3_bind_text(s,1,role.UTF8String,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,2,title.UTF8String,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,3,identifier.UTF8String,-1,SQLITE_TRANSIENT); rc = sqlite3_step(s);
        }
        sqlite3_finalize(s);
        if (rc == SQLITE_DONE) rc = sqlite3_exec(db,"COMMIT",NULL,NULL,NULL);
        if (rc != SQLITE_OK) { sqlite3_exec(db,"ROLLBACK",NULL,NULL,NULL); *error = @"Database write failed"; return nil; }
        return @{@"saved":@YES};
    }
    *error = @"Method denied or unknown";
    return nil;
}
static void serve(int fd) {
    struct timeval timeout = {5, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    uid_t uid; gid_t gid;
    if (getpeereid(fd, &uid, &gid) || uid != getuid()) return;
    NSMutableData *data = [NSMutableData data];
    char c;
    while (data.length < AHMaxFrame) {
        if (read(fd, &c, 1) != 1) return;
        if (c == '\n') break;
        [data appendBytes:&c length:1];
    }
    if (c != '\n') return;
    id request = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *error = nil;
    id result = nil;
    BOOL valid = [request isKindOfClass:NSDictionary.class] && [request[@"id"] isKindOfClass:NSString.class] && [request[@"method"] isKindOfClass:NSString.class] && [request[@"params"] isKindOfClass:NSDictionary.class];
    if (valid) {
        __block id responseResult=nil; __block NSString *responseError=nil;
        dispatch_sync(dispatch_get_main_queue(),^{
            @try { responseResult=execute(request[@"method"],request[@"params"],&responseError); }
            @catch(NSException *exception) { NSLog(@"AgentHome IPC %@ failed: %@",request[@"method"],exception.name); responseError=@"Daemon gặp lỗi xử lý yêu cầu; dữ liệu vẫn được giữ. Hãy báo tên thao tác đang dùng."; }
        });
        result=responseResult; error=responseError;
    }
    else error = @"Invalid request";
    NSMutableDictionary *response = [@{@"id": valid ? request[@"id"] : @""} mutableCopy];
    response[error ? @"error" : @"result"] = error ?: result;
    NSMutableData *out = [[NSJSONSerialization dataWithJSONObject:response options:0 error:nil] mutableCopy];
    [out appendBytes:"\n" length:1];
    const char *p = out.bytes; NSUInteger remaining = out.length;
    while (remaining) { ssize_t n = write(fd, p, remaining); if (n <= 0) break; p += n; remaining -= n; }
}
static void runQueuedTasks(void) {
    for(;;) { @autoreleasepool {
        sqlite3_stmt *s=NULL;
        if(sqlite3_prepare_v2(db,"SELECT id FROM tasks WHERE state='queued' AND tool='system.info' ORDER BY rowid LIMIT 1",-1,&s,NULL)!=SQLITE_OK) return;
        NSString *identifier=nil;
        if(sqlite3_step(s)==SQLITE_ROW) identifier=@((const char *)sqlite3_column_text(s,0));
        sqlite3_finalize(s); if(!identifier) return;
        if(AHTaskTransition(db,identifier.UTF8String,"queued","running","","Executing read-only capability")!=SQLITE_OK) return;
        NSString *error=nil; id info=execute(@"system.info",@{},&error);
        NSString *result=info?[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:info options:0 error:nil] encoding:NSUTF8StringEncoding]:error;
        if(AHTaskTransition(db,identifier.UTF8String,"running",info?"completed":"failed",result.UTF8String,info?"Result persisted":"Capability failed")!=SQLITE_OK) return;
    } }
}
int main(void) { @autoreleasepool {
    signal(SIGPIPE, SIG_IGN); umask(0077);
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:AHDataPath withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:&error]) return 1;
    if (sqlite3_open([AHDataPath stringByAppendingPathComponent:@"memory.sqlite"].UTF8String, &db) != SQLITE_OK) return 2;
    if (AHMigrate(db) != SQLITE_OK) return 3;
    if(AHTaskRecover(db)!=SQLITE_OK) return 6;
    compaction=[[AHCompaction alloc] initWithDatabase:db];
    agent=[[AHAgentRuntime alloc] initWithDatabase:db tool:^NSDictionary *(NSString *name){ NSString *error=nil; return execute(name,@{},&error); }];
    web=[[AHWebServer alloc] initWithDatabase:db rpc:^id(NSString *method,NSDictionary *params,NSString **error){
        @try { return execute(method,params,error); }
        @catch(NSException *exception) { NSLog(@"AgentHome web RPC %@ failed: %@",method,exception.name); if(error) *error=@"Daemon gặp lỗi xử lý request; hãy báo tên thao tác."; return nil; }
    }];
    [agent recoverAndStart];
    runQueuedTasks();
    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un address = {0}; address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, AHSocketPath, sizeof(address.sun_path));
    unlink(AHSocketPath);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) || chmod(AHSocketPath, 0600) || listen(listener, 8)) return 4;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        for (;;) { int fd=accept(listener,NULL,NULL); if(fd<0) { if(errno==EINTR) continue; _exit(5); }
            @autoreleasepool { serve(fd); } close(fd);
            dispatch_sync(dispatch_get_main_queue(),^{ runQueuedTasks(); });
        }
    });
    dispatch_main();
} }
