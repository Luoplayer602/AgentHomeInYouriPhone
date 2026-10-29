#include "../shared/AHDatabase.h"
#include <cassert>
#include <iostream>
static int count(sqlite3 *db,const char *sql) { sqlite3_stmt *s=0; assert(sqlite3_prepare_v2(db,sql,-1,&s,0)==SQLITE_OK); assert(sqlite3_step(s)==SQLITE_ROW); int n=sqlite3_column_int(s,0); sqlite3_finalize(s); return n; }
int main() {
    (void)AHMessagesSQL; (void)AHConversationsSQL; (void)AHInsertSQL;
    sqlite3 *db=0; assert(sqlite3_open(":memory:",&db)==SQLITE_OK); assert(AHMigrate(db)==SQLITE_OK);
    assert(AHTaskCreate(db,"one","legacy")==SQLITE_OK);
    assert(AHTaskTransition(db,"one","queued","running","","Start")==SQLITE_OK);
    assert(AHTaskRecover(db)==SQLITE_OK);
    assert(count(db,"SELECT count(*) FROM tasks WHERE state='queued'")==1);
    assert(AHTaskTransition(db,"one","queued","running","","Resume")==SQLITE_OK);
    assert(AHTaskTransition(db,"one","running","completed","{\"ok\":true}","Done")==SQLITE_OK);
    assert(AHTaskTransition(db,"one","running","completed","bad","Repeated")==SQLITE_CONSTRAINT);
    assert(count(db,"SELECT count(*) FROM task_events WHERE task_id='one'")==5);
    assert(AHTaskCreate(db,"missing","unknown")!=SQLITE_OK);
    assert(count(db,"SELECT count(*) FROM tasks")==1);
    assert(AHTaskCreate(db,"remote","legacy")==SQLITE_OK);
    assert(sqlite3_exec(db,"UPDATE tasks SET tool='chat.ai',state='running' WHERE id='remote'",0,0,0)==SQLITE_OK);
    assert(AHTaskRecover(db)==SQLITE_OK);
    assert(count(db,"SELECT count(*) FROM tasks WHERE id='remote' AND state='running'")==1);
    // Upgrade the pre-reasoning ai_runs schema without losing its partial.
    assert(sqlite3_exec(db,"DROP TABLE ai_runs; CREATE TABLE ai_runs(task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,config TEXT NOT NULL,context TEXT NOT NULL,partial TEXT NOT NULL DEFAULT '',round INTEGER NOT NULL DEFAULT 0); INSERT INTO ai_runs(task_id,config,context,partial) VALUES ('remote','{}','[]','saved partial')",0,0,0)==SQLITE_OK);
    assert(AHMigrate(db)==SQLITE_OK);
    assert(count(db,"SELECT count(*) FROM ai_runs WHERE task_id='remote' AND partial='saved partial' AND reasoning=''")==1);
    sqlite3_close(db);
    // Reopen an actual file to ensure queued work survives process/database closure.
    const char *path="/tmp/agenthome-task-test.sqlite"; std::remove(path);
    assert(sqlite3_open(path,&db)==SQLITE_OK); assert(AHMigrate(db)==SQLITE_OK); assert(AHTaskCreate(db,"persist","legacy")==SQLITE_OK); sqlite3_close(db);
    assert(sqlite3_open(path,&db)==SQLITE_OK); assert(AHMigrate(db)==SQLITE_OK); assert(count(db,"SELECT count(*) FROM tasks WHERE state='queued'")==1); sqlite3_close(db); std::remove(path);
    std::cout<<"PASS tasks: enqueue, audit, restart recovery, persisted queue, guarded transitions, unknown conversation rollback\n";
}
