#import <Foundation/Foundation.h>
#import <sqlite3.h>
// Cursor walks recent history without a message-count cap; bounds RAM on older phones.
static inline NSArray *AHHistory(sqlite3 *db, NSString *conversation, NSString *end) {
    sqlite3_stmt *statement=NULL; NSMutableArray *history=[NSMutableArray array]; NSUInteger bytes=0;
    if(sqlite3_prepare_v2(db,"SELECT role,content FROM messages WHERE conversation_id=? AND id>? ORDER BY id DESC",-1,&statement,NULL)==SQLITE_OK) {
        sqlite3_bind_text(statement,1,conversation.UTF8String,-1,SQLITE_TRANSIENT);
        sqlite3_bind_text(statement,2,end.UTF8String,-1,SQLITE_TRANSIENT);
        while(sqlite3_step(statement)==SQLITE_ROW) {
            NSUInteger length=sqlite3_column_bytes(statement,1); if(bytes+length>4*1024*1024) break; bytes+=length;
            const char *role=(const char *)sqlite3_column_text(statement,0), *content=(const char *)sqlite3_column_text(statement,1);
            [history addObject:@{@"role":role?@(role):@"user",@"content":content?@(content):@""}];
        }
    }
    sqlite3_finalize(statement); return [[history reverseObjectEnumerator] allObjects];
}
