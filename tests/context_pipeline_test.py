"""Execute actual migration/usage/auto-intent SQL; no model calls."""
import ast,json,re,sqlite3
from pathlib import Path
schema=Path('shared/AHDatabase.h').read_text()
sql=next(ast.literal_eval(s) for s in re.findall(r'sqlite3_exec\(db,("(?:[^"\\]|\\.)*")',schema) if 'CREATE TABLE IF NOT EXISTS request_usage' in s)
db=sqlite3.connect(':memory:',isolation_level=None)
db.executescript("PRAGMA foreign_keys=ON; CREATE TABLE conversations(id TEXT PRIMARY KEY); CREATE TABLE tasks(id TEXT PRIMARY KEY,conversation_id TEXT REFERENCES conversations(id) ON DELETE CASCADE); INSERT INTO conversations VALUES ('a'),('b'); INSERT INTO tasks VALUES ('one','a');")
db.executescript(sql)
usage=Path('daemon/AHUsage.m').read_text()
insert=re.search(r'@?"(INSERT OR REPLACE INTO request_usage[^"\n]+)"',usage).group(1)
aggregate=re.search(r'@?"(SELECT count\(\*\),coalesce\(sum\(input_tokens\)[^"\n]+)"',usage).group(1)
for round_,tokens in enumerate([1500,1700]): db.execute(insert,('one',round_,'profile-a',tokens,10,1000,'{}'))
assert db.execute(aggregate,('profile-a',)).fetchone()[:5]==(2,3200,20,1700,1710)
assert db.execute(aggregate,('profile-b',)).fetchone()[0]==0
# Stable task+round cannot double count a retried usage observation.
db.execute(insert,('one',1,'profile-a',1700,10,1000,'{}'))
assert db.execute(aggregate,('profile-a',)).fetchone()[0]==2
context=Path('daemon/AHCompaction.m').read_text()
intent=re.search(r'@"(INSERT OR REPLACE INTO context_auto_runs\([^"\n]+Preparing[^"\n]+)"',context).group(1)
db.execute(intent,('a','one',1234.0))
assert db.execute('SELECT last_task,job_id FROM context_auto_runs').fetchone()==('one','')
# Restart can see the durable intent even before the job ID was saved.
assert 'if([previous[@"last_task"] isEqual:task])' in context
settings=re.search(r'@"(INSERT OR REPLACE INTO context_settings\([^"\n]+)"',context).group(1)
db.execute(settings,('*',0,80,0));db.execute(settings,('a',1,50,1))
query=re.search(r'@"(SELECT enabled,threshold,auto_activate FROM context_settings[^"\n]+)"',context).group(1)
assert db.execute(query,('a','a')).fetchone()==(1,50,1)
assert db.execute(query,('b','b')).fetchone()==(0,80,0)
db.execute("DELETE FROM conversations WHERE id='a'")
assert db.execute('SELECT count(*) FROM request_usage').fetchone()[0]==0
assert db.execute('SELECT count(*) FROM context_auto_runs').fetchone()[0]==0
print('PASS context pipeline SQL: per-round usage, provider isolation, dedupe, durable auto intent, scoped settings, deletion cascade')
