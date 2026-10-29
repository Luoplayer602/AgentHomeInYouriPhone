#pragma once
#include <sqlite3.h>
static const char *AHTaskSchema =
"CREATE TABLE IF NOT EXISTS tasks(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,tool TEXT NOT NULL DEFAULT 'system.info',state TEXT NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','running','completed','failed','cancelled')),result TEXT NOT NULL DEFAULT '',created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);"
"CREATE TABLE IF NOT EXISTS task_events(id INTEGER PRIMARY KEY,task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,state TEXT NOT NULL,note TEXT NOT NULL,created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);"
"CREATE TABLE IF NOT EXISTS ai_runs(task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,config TEXT NOT NULL,context TEXT NOT NULL,partial TEXT NOT NULL DEFAULT '',round INTEGER NOT NULL DEFAULT 0);";
static inline int AHTaskEvent(sqlite3 *db,const char *id,const char *state,const char *note) {
    sqlite3_stmt *s=0; int rc=sqlite3_prepare_v2(db,"INSERT INTO task_events(task_id,state,note) VALUES (?,?,?)",-1,&s,0);
    if(rc==SQLITE_OK) { sqlite3_bind_text(s,1,id,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,2,state,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,3,note,-1,SQLITE_TRANSIENT); rc=sqlite3_step(s); }
    sqlite3_finalize(s); return rc==SQLITE_DONE?SQLITE_OK:rc;
}
static inline int AHTaskCreate(sqlite3 *db,const char *id,const char *conversation) {
    int rc=sqlite3_exec(db,"BEGIN IMMEDIATE",0,0,0); sqlite3_stmt *s=0;
    if(rc==SQLITE_OK) rc=sqlite3_prepare_v2(db,"INSERT INTO tasks(id,conversation_id) VALUES (?,?)",-1,&s,0);
    if(rc==SQLITE_OK) { sqlite3_bind_text(s,1,id,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,2,conversation,-1,SQLITE_TRANSIENT); rc=sqlite3_step(s); }
    sqlite3_finalize(s); if(rc==SQLITE_DONE) rc=AHTaskEvent(db,id,"queued","Accepted: read-only system.info, risk 0");
    if(rc==SQLITE_OK) rc=sqlite3_exec(db,"COMMIT",0,0,0);
    if(rc!=SQLITE_OK) sqlite3_exec(db,"ROLLBACK",0,0,0);
    return rc;
}
static inline int AHTaskTransition(sqlite3 *db,const char *id,const char *from,const char *to,const char *result,const char *note) {
    int rc=sqlite3_exec(db,"BEGIN IMMEDIATE",0,0,0); sqlite3_stmt *s=0;
    if(rc==SQLITE_OK) rc=sqlite3_prepare_v2(db,"UPDATE tasks SET state=?,result=?,updated_at=CURRENT_TIMESTAMP WHERE id=? AND state=?",-1,&s,0);
    if(rc==SQLITE_OK) { sqlite3_bind_text(s,1,to,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,2,result,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,3,id,-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,4,from,-1,SQLITE_TRANSIENT); rc=sqlite3_step(s); }
    int changed=sqlite3_changes(db); sqlite3_finalize(s);
    if(rc==SQLITE_DONE) rc=changed==1?AHTaskEvent(db,id,to,note):SQLITE_CONSTRAINT;
    if(rc==SQLITE_OK) rc=sqlite3_exec(db,"COMMIT",0,0,0);
    if(rc!=SQLITE_OK) sqlite3_exec(db,"ROLLBACK",0,0,0);
    return rc;
}
static inline int AHTaskRecover(sqlite3 *db) {
    // Retrying is allowed only because this milestone has one read-only tool.
    int rc=sqlite3_exec(db,"BEGIN IMMEDIATE; INSERT INTO task_events(task_id,state,note) SELECT id,'queued','Recovered read-only task after daemon restart' FROM tasks WHERE state='running' AND tool='system.info'; UPDATE tasks SET state='queued',updated_at=CURRENT_TIMESTAMP WHERE state='running' AND tool='system.info'; COMMIT",0,0,0);
    if(rc!=SQLITE_OK) sqlite3_exec(db,"ROLLBACK",0,0,0);
    return rc;
}
