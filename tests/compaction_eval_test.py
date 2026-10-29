"""Test the scorer using authored fixtures; these are not model quality results."""
import importlib.util
import json
from pathlib import Path
spec=importlib.util.spec_from_file_location('evaluator','scripts/evaluate-compaction.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
cases=json.loads(Path('tests/fixtures/compaction-evals.json').read_text())
for case in cases:
    assert module.score(case,case['reference_summary'])['passed']
    assert not module.score(case,'Đã xong mọi thứ')['passed']
    assert not module.score(case,'')['passed']
    for forbidden in case['forbidden']:
        assert not module.score(case,case['reference_summary']+' '+forbidden)['passed']
print('PASS eval scorer: required facts, missing summaries, untrusted marker/secret leakage; authored fixtures only')
retest=json.loads(Path('tests/fixtures/compaction-live-retest.json').read_text())
control=module.score_recall(retest['expected_recall'],retest['control_recall'])
compacted=module.score_recall(retest['expected_recall'],retest['actual_recall'])
assert control['passed'] and control['correct']==9
assert not compacted['passed'] and compacted['wrong_fields']==['report_path','build_verified']
assert compacted['correct']==7
assert not module.score_recall({'build_verified':False},{'build_verified':'false'})['passed']
print('PASS scorer regression: live control 9/9; compacted reply 7/9, detects lost path and false verification')
# Live eval request schema changed: references are materialized by lookup, not
# by trusting provider-written quote text. This is fixture preflight, not native validation.
catalog=module.fixture_catalog(cases[0])
selection={key:[] for key in module.SELECTION_SECTIONS};selection['selection_version']=1
selection['work_state']=['S2','S2']
materialized=module.fixture_materialize(json.dumps(selection),catalog)
assert materialized==catalog[1]['content']
selection['work_state']=['unknown']
try: module.fixture_materialize(json.dumps(selection),catalog)
except ValueError: pass
else: raise AssertionError('unknown selection ID accepted')
selection['work_state']=[{'source_id':'S2','quote':'invented'}]
try: module.fixture_materialize(json.dumps(selection),catalog)
except ValueError: pass
else: raise AssertionError('provider quote accepted')
assert all('TEST_SECRET_NEVER_INCLUDE_7' not in row['content'] for row in module.fixture_catalog(cases[1]))
import ast,re
instruction=ast.literal_eval(re.search(r'stringWithFormat:@("(?:[^"\\]|\\.)*")',Path('daemon/AHCompactPlan.m').read_text()).group(1))
assert '"selection_version":1' in instruction and 'permissions' in instruction
print('PASS eval selection protocol: exact fixture lookup, dedupe, rejects quotes/unknown IDs, filters labeled secrets, complete escaped JSON instruction')
latest=json.loads(Path('tests/fixtures/memory-v013-live.json').read_text())
latest_score=module.score_recall(latest['expected_recall'],latest['actual_recall'])
assert not latest_score['passed'] and latest_score['correct']==8 and latest_score['wrong_fields']==['project_id']
quotes='\n'.join(entry['quote'] for values in latest['memory'].values() if isinstance(values,list) for entry in values)
for fact in ['LOTUS-482','/tmp/agenthome-eval/report.txt','/v1/chat/completions','NOT done']:
    assert fact in quotes
assert 'TEST_SECRET_NEVER_INCLUDE_7' not in quotes and 'WEB_GRANTED_DEPLOY' not in quotes
assert latest['focused_project_probe']['answer'].strip()=='LOTUS-482'
print('PASS live 0.13 scorer regression: memory retains facts, bulk recall 8/9, focused project lookup correct; no false 9/9 claim')
