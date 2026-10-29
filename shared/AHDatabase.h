#pragma once
#include <sqlite3.h>
#include "AHTasks.h"
// Shared by daemon and host migration tests. Existing history stays in legacy.
static const char *AHMessagesSQL = "SELECT role,content FROM messages WHERE conversation_id=? ORDER BY id DESC LIMIT 100";
static const char *AHConversationsSQL = "SELECT id,title,pinned,accessed_at FROM conversations ORDER BY pinned DESC,accessed_at DESC,rowid DESC LIMIT 200";
static const char *AHInsertSQL = "INSERT INTO messages(role,content,conversation_id) VALUES (?,?,?)";
static inline int AHAddColumn(sqlite3 *db,const char *column,const char *sql) {
    sqlite3_stmt *s=0; int found=0;
    int rc=sqlite3_prepare_v2(db,"PRAGMA table_info(conversations)",-1,&s,0);
    if(rc==SQLITE_OK) while(sqlite3_step(s)==SQLITE_ROW) if(sqlite3_stricmp((const char *)sqlite3_column_text(s,1),column)==0) found=1;
    sqlite3_finalize(s);
    return rc==SQLITE_OK && !found ? sqlite3_exec(db,sql,0,0,0) : rc;
}
static inline int AHMigrate(sqlite3 *db) {
    int rc = sqlite3_exec(db, "PRAGMA foreign_keys=OFF; PRAGMA journal_mode=WAL; BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS conversations(id TEXT PRIMARY KEY,title TEXT NOT NULL,updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))); INSERT OR IGNORE INTO conversations(id,title) SELECT 'legacy','Hội thoại cũ' WHERE NOT EXISTS(SELECT 1 FROM conversations); CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY,role TEXT NOT NULL,content TEXT NOT NULL,created_at TEXT DEFAULT CURRENT_TIMESTAMP,conversation_id TEXT NOT NULL DEFAULT 'legacy' REFERENCES conversations(id));", 0, 0, 0);
    if (rc != SQLITE_OK) { sqlite3_exec(db, "ROLLBACK; PRAGMA foreign_keys=ON", 0, 0, 0); return rc; }
    sqlite3_stmt *s = 0; int found = 0;
    rc = sqlite3_prepare_v2(db, "PRAGMA table_info(messages)", -1, &s, 0);
    if (rc == SQLITE_OK) {
        while (sqlite3_step(s) == SQLITE_ROW) {
            const unsigned char *name = sqlite3_column_text(s,1);
            if (name && sqlite3_stricmp((const char *)name,"conversation_id") == 0) found = 1;
        }
    }
    sqlite3_finalize(s);
    if (rc == SQLITE_OK && !found) rc = sqlite3_exec(db, "ALTER TABLE messages ADD COLUMN conversation_id TEXT NOT NULL DEFAULT 'legacy' REFERENCES conversations(id)", 0, 0, 0);
    if (rc == SQLITE_OK) rc = AHAddColumn(db,"pinned","ALTER TABLE conversations ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0");
    if (rc == SQLITE_OK) rc = AHAddColumn(db,"accessed_at","ALTER TABLE conversations ADD COLUMN accessed_at REAL NOT NULL DEFAULT 0");
    if (rc == SQLITE_OK) rc = sqlite3_exec(db,"UPDATE conversations SET accessed_at=updated_at WHERE accessed_at=0",0,0,0);
    if (rc == SQLITE_OK) rc = sqlite3_exec(db,AHTaskSchema,0,0,0);
    if(rc==SQLITE_OK) {
        sqlite3_stmt *r=0; int hasReasoning=0;
        rc=sqlite3_prepare_v2(db,"PRAGMA table_info(ai_runs)",-1,&r,0);
        if(rc==SQLITE_OK) while(sqlite3_step(r)==SQLITE_ROW) if(sqlite3_stricmp((const char *)sqlite3_column_text(r,1),"reasoning")==0) hasReasoning=1;
        sqlite3_finalize(r);
        if(rc==SQLITE_OK && !hasReasoning) rc=sqlite3_exec(db,"ALTER TABLE ai_runs ADD COLUMN reasoning TEXT NOT NULL DEFAULT ''",0,0,0);
    }
    if (rc == SQLITE_OK) rc = sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS messages_conversation ON messages(conversation_id,id); PRAGMA user_version=5; COMMIT", 0, 0, 0);
    if (rc != SQLITE_OK) sqlite3_exec(db, "ROLLBACK", 0, 0, 0);
    sqlite3_exec(db, "PRAGMA foreign_keys=ON", 0, 0, 0);
    return rc;
}
