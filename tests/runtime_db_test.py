"""Exercise the exact SQL used by AHAgentRuntime against host SQLite."""
import ast
import json
import re
import sqlite3
from pathlib import Path

source = Path('daemon/AHAgentRuntime.m').read_text()
queries = re.findall(r'\[self sql:@"([^"\n]+)" values:', source)
def query(prefix):
    return next(sql for sql in queries if sql.startswith(prefix))

schema = Path('shared/AHTasks.h').read_text().split('static inline')[0]
schema = ''.join(ast.literal_eval(s) for s in re.findall(r'"(?:[^"\\]|\\.)*"', schema))
db = sqlite3.connect(':memory:', isolation_level=None)
db.execute('PRAGMA foreign_keys=ON')
db.executescript('''CREATE TABLE conversations(id TEXT PRIMARY KEY,title TEXT,accessed_at REAL);
CREATE TABLE messages(id INTEGER PRIMARY KEY,role TEXT,content TEXT,conversation_id TEXT REFERENCES conversations(id));
INSERT INTO conversations VALUES ('a','Hội thoại mới',0),('b','Hội thoại mới',0);''')
db.executescript(schema)
profile = dict(id='profile', endpoint='https://example.test/v1/chat/completions', model='test')

def submit(identifier, conversation):
    db.execute('BEGIN IMMEDIATE')
    try:
        db.execute(query('INSERT INTO tasks(id,conversation_id,tool)'), (identifier, conversation))
        db.execute(query('INSERT INTO messages(role,content,conversation_id) VALUES'), ('hello', conversation))
        db.execute(query('INSERT INTO ai_runs'), (identifier, json.dumps(profile), '[]'))
        db.execute('COMMIT')
    except sqlite3.Error:
        db.execute('ROLLBACK')
        raise

submit('one', 'a')
try:
    submit('one', 'a')
except sqlite3.IntegrityError:
    pass
assert db.execute('SELECT count(*) FROM messages').fetchone()[0] == 1
submit('two', 'b')
db.execute("UPDATE tasks SET state='running' WHERE id='one'")
db.execute(query('UPDATE ai_runs SET partial=?,context=?,round=?'), ('Chào bạn', '[]', 1, 'one'))
# Successful completion: transcript insert and terminal state commit atomically.
db.execute('BEGIN IMMEDIATE')
db.execute(query("INSERT INTO messages(role,content,conversation_id) SELECT 'assistant',?,"), ('answer', 'one'))
db.execute(query('UPDATE tasks SET state=?,result=?'), ('completed', '', 'one'))
db.execute('COMMIT')
assert db.execute("SELECT content FROM messages WHERE conversation_id='a' AND role='assistant'").fetchall() == [('answer',)]
# Conditional insert prevents duplicate assistant text if a terminal run is visited again.
db.execute(query("INSERT INTO messages(role,content,conversation_id) SELECT 'assistant',?,"), ('duplicate', 'one'))
assert db.execute("SELECT count(*) FROM messages WHERE role='assistant'").fetchone()[0] == 1
# Interrupted remote request: recover partial exactly once, fail, never requeue.
db.execute("UPDATE tasks SET state='running' WHERE id='two'")
db.execute(query('UPDATE ai_runs SET partial=?,context=?,round=?'), ('partial', '[]', 0, 'two'))
recovery = source.split('- (void)recoverAndStart')[1].split('- (id)handle:')[0]
recover_queries = re.findall(r'\[self sql:@"([^"\n]+)" values:', recovery)
for _ in range(2):
    for sql in recover_queries:
        db.execute(sql)
assert db.execute("SELECT state FROM tasks WHERE id='two'").fetchone()[0] == 'failed'
assert len(db.execute("SELECT content FROM messages WHERE conversation_id='b' AND role='assistant'").fetchall()) == 1
assert 'api-key' not in db.execute('SELECT config FROM ai_runs LIMIT 1').fetchone()[0]
print('PASS runtime SQL: atomic enqueue, duplicate ID rollback, conversation isolation, completion dedupe, checkpoint, restart without remote replay')
