"""Execute the schema and state-changing SQL used by compact on host SQLite."""
import ast
import re
import sqlite3
from pathlib import Path
source=Path('daemon/AHCompaction.m').read_text()
queries=re.findall(r'\[self sql:@"([^"\n]+)" values:',source)
def sql(prefix): return next(q for q in queries if q.startswith(prefix))
schema=Path('shared/AHDatabase.h').read_text()
statement=next(ast.literal_eval(q) for q in re.findall(r'sqlite3_exec\(db,("(?:[^"\\]|\\.)*")',schema) if 'CREATE TABLE IF NOT EXISTS compactions' in q)
db=sqlite3.connect(':memory:',isolation_level=None)
db.execute('PRAGMA foreign_keys=ON')
db.executescript("CREATE TABLE conversations(id TEXT PRIMARY KEY); CREATE TABLE tasks(id TEXT PRIMARY KEY); CREATE TABLE messages(id INTEGER PRIMARY KEY,conversation_id TEXT,role TEXT,content TEXT); INSERT INTO conversations VALUES ('a'),('b');")
db.executescript(statement)
for i in range(10): db.execute('INSERT INTO messages(conversation_id,role,content) VALUES (?,?,?)',('a','user' if i%2==0 else 'assistant',f'message {i}'))
original=db.execute('SELECT * FROM messages').fetchall()
def create(job,conversation,base=''):
 db.execute(sql('INSERT INTO compactions('),(job,conversation,6,'hash',base,'provider','model',1000))
def ready(job): db.execute(sql("UPDATE compactions SET state='ready'"),('summary',100,job))
def activate(job,conversation):
 db.execute('BEGIN IMMEDIATE')
 db.execute(sql("UPDATE compactions SET state='superseded'"),(conversation,))
 db.execute(sql("UPDATE compactions SET state='active'"),(job,))
 db.execute('COMMIT')
create('one','a');ready('one');activate('one','a')
create('cancel','a','one')
db.execute(sql("UPDATE compactions SET state='discarded' WHERE id=? AND state IN"),('cancel',))
assert db.execute("SELECT state FROM compactions WHERE id='one'").fetchone()[0]=='active'
create('pending','a','one')
# Restart marks only incomplete compact failed and preserves the active snapshot.
db.execute(sql("UPDATE compactions SET state='failed',error='Daemon restarted"))
assert db.execute("SELECT state FROM compactions WHERE id='one'").fetchone()[0]=='active'
assert db.execute("SELECT state FROM compactions WHERE id='pending'").fetchone()[0]=='failed'
create('two','a','one');ready('two');activate('two','a')
assert db.execute("SELECT id FROM compactions WHERE conversation_id='a' AND state='active'").fetchall()==[('two',)]
create('other','b');ready('other');activate('other','b')
# Boundary used by the real runtime: retained recent messages remain separate.
runtime=Path('daemon/AHHistory.h').read_text()
query=re.search(r'"(SELECT role,content FROM messages WHERE conversation_id=\? AND id>\? ORDER BY id DESC)"',runtime).group(1)
assert len(db.execute(query,('a',6)).fetchall())==4
# Failed activation transaction must keep prior active state.
try:
 db.execute('BEGIN IMMEDIATE');db.execute("UPDATE compactions SET state='superseded' WHERE id='two'");db.execute("UPDATE compactions SET state=NULL WHERE id='one'");db.execute('COMMIT')
except sqlite3.IntegrityError: db.execute('ROLLBACK')
assert db.execute("SELECT state FROM compactions WHERE id='two'").fetchone()[0]=='active'
db.execute(sql("UPDATE compactions SET state='discarded' WHERE conversation_id="),('a',))
assert db.execute("SELECT state FROM compactions WHERE id='other'").fetchone()[0]=='active'
assert db.execute('SELECT * FROM messages').fetchall()==original
print('PASS compact SQL: source history unchanged, active snapshot isolation, ready/apply/drop, restart preserves old summary, rollback, retained message boundary')
planner=Path('daemon/AHCompactPlan.m').read_text()
boundary_query=re.search(r'"(SELECT id FROM messages WHERE conversation_id=\? AND id>\? ORDER BY id DESC LIMIT 1 OFFSET 4)"',planner).group(1)
source_query=re.search(r'"(SELECT id,role,content FROM messages WHERE conversation_id=\? AND id>\? AND id<=\? ORDER BY id)"',planner).group(1)
for i in range(300): db.execute('INSERT INTO messages(conversation_id,role,content) VALUES (?,?,?)',('long','user' if i%2==0 else 'assistant','x'*1000))
boundary=db.execute(boundary_query,('long',0)).fetchone()[0]
rows=db.execute(source_query,('long',0,boundary)).fetchall()
assert len(rows)==296 and rows[-1][1]=='assistant'
assert db.execute('SELECT count(*) FROM messages WHERE conversation_id=? AND id>?',('long',boundary)).fetchone()[0]==4
assert not db.execute(boundary_query,('long',boundary)).fetchall()
assert len(db.execute(source_query,('a',6,8)).fetchall())==2
print('PASS compact planner SQL: contiguous prefix, >200 messages, retain four newest, active-summary boundary')
