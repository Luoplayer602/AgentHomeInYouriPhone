#include "../shared/AHDatabase.h"
#include <cassert>
#include <iostream>
#include <string>
static void sql(sqlite3 *db,const char *query) { assert(sqlite3_exec(db,query,0,0,0)==SQLITE_OK); }
int main() {
    for (int version : {0,1,2}) {
        bool legacy=version!=0;
        sqlite3 *db=nullptr; assert(sqlite3_open(":memory:",&db)==SQLITE_OK);
        if (legacy) sql(db,"CREATE TABLE messages(id INTEGER PRIMARY KEY,role TEXT NOT NULL,content TEXT NOT NULL,created_at TEXT DEFAULT CURRENT_TIMESTAMP); INSERT INTO messages(role,content) VALUES ('user','old history');");
        if(version==2) {
            sql(db,"CREATE TABLE conversations(id TEXT PRIMARY KEY,title TEXT NOT NULL,updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))); INSERT INTO conversations(id,title) VALUES ('legacy','Hội thoại cũ'); ALTER TABLE messages ADD COLUMN conversation_id TEXT NOT NULL DEFAULT 'legacy' REFERENCES conversations(id);");
        }
        assert(AHMigrate(db)==SQLITE_OK); assert(AHMigrate(db)==SQLITE_OK);
        sql(db,"INSERT INTO conversations(id,title) VALUES ('a','A'),('b','B');");
        sqlite3_stmt *s=nullptr;
        assert(sqlite3_prepare_v2(db,AHInsertSQL,-1,&s,0)==SQLITE_OK);
        for (const char *id : {"a","b"}) {
            sqlite3_bind_text(s,1,"user",-1,SQLITE_STATIC); sqlite3_bind_text(s,2,id,-1,SQLITE_STATIC); sqlite3_bind_text(s,3,id,-1,SQLITE_STATIC);
            assert(sqlite3_step(s)==SQLITE_DONE); sqlite3_reset(s);
        }
        sqlite3_finalize(s);
        assert(sqlite3_prepare_v2(db,AHMessagesSQL,-1,&s,0)==SQLITE_OK);
        for (const char *id : {"a","b","legacy"}) {
            sqlite3_bind_text(s,1,id,-1,SQLITE_STATIC);
            int rc=sqlite3_step(s);
            if (std::string(id)=="legacy" && !legacy) assert(rc==SQLITE_DONE);
            else { assert(rc==SQLITE_ROW); assert(std::string((const char *)sqlite3_column_text(s,1))==(std::string(id)=="legacy" ? "old history" : id)); assert(sqlite3_step(s)==SQLITE_DONE); }
            sqlite3_reset(s);
        }
        sqlite3_finalize(s);
        assert(sqlite3_prepare_v2(db,AHConversationsSQL,-1,&s,0)==SQLITE_OK);
        int count=0; while (sqlite3_step(s)==SQLITE_ROW) ++count; assert(count==3);
        sqlite3_finalize(s);
        assert(sqlite3_exec(db,"INSERT INTO messages(role,content,conversation_id) VALUES ('user','x','missing')",0,0,0)==SQLITE_CONSTRAINT);
        sql(db,"UPDATE conversations SET accessed_at=1,pinned=0; UPDATE conversations SET accessed_at=100 WHERE id='b'; UPDATE conversations SET pinned=1 WHERE id='a';");
        assert(sqlite3_prepare_v2(db,AHConversationsSQL,-1,&s,0)==SQLITE_OK);
        assert(sqlite3_step(s)==SQLITE_ROW && std::string((const char *)sqlite3_column_text(s,0))=="a");
        assert(sqlite3_step(s)==SQLITE_ROW && std::string((const char *)sqlite3_column_text(s,0))=="b"); sqlite3_finalize(s);
        sql(db,"UPDATE conversations SET pinned=0 WHERE id='a';");
        assert(sqlite3_prepare_v2(db,AHConversationsSQL,-1,&s,0)==SQLITE_OK);
        assert(sqlite3_step(s)==SQLITE_ROW && std::string((const char *)sqlite3_column_text(s,0))=="b"); sqlite3_finalize(s);
        sql(db,"BEGIN; DELETE FROM messages WHERE conversation_id='b'; DELETE FROM conversations WHERE id='b'; COMMIT;");
        assert(AHMigrate(db)==SQLITE_OK);
        assert(sqlite3_prepare_v2(db,"SELECT count(*) FROM conversations WHERE id='b'",-1,&s,0)==SQLITE_OK);
        assert(sqlite3_step(s)==SQLITE_ROW && sqlite3_column_int(s,0)==0); sqlite3_finalize(s);
        sqlite3_close(db);
    }
    std::cout<<"PASS database: fresh install, legacy migration, idempotence, history preservation, isolation, pin priority, access ordering, deletion, foreign key\n";
}
