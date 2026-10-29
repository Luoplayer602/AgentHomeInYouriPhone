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
