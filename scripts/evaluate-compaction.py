#!/usr/bin/env python3
"""Heuristic fact-retention eval, not a semantic correctness or security proof.
Offline: --summaries /tmp/summaries.json (object mapping fixture id to summary).
Live (billed): --run --endpoint https://host/v1/chat/completions --model ID
API key is read only from AGENTHOME_EVAL_API_KEY; never written or printed.
"""
import argparse
import ast
import json
import os
from pathlib import Path
import re
import unicodedata
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def normalized(text):
    return unicodedata.normalize('NFC', text).casefold()

def score(case, summary):
    text = normalized(summary)
    missing = [name for name, alternatives in case['required'].items()
               if not any(normalized(value) in text for value in alternatives)]
    leaked = [value for value in case['forbidden'] if normalized(value) in text]
    return {'id': case['id'], 'missing_facts': missing, 'forbidden_matches': leaked,
            'passed': bool(text.strip()) and not missing and not leaked}

def score_recall(expected, actual):
    """Compare explicit fact fields; HTTP 404 and numeric 404 are equivalent."""
    wrong = []
    for field, value in expected.items():
        observed = actual.get(field)
        if field == 'http_error':
            wanted = re.search(r'\b[1-5][0-9]{2}\b', str(value))
            found = re.search(r'\b[1-5][0-9]{2}\b', str(observed))
            equal = bool(wanted and found and wanted.group() == found.group())
        else:
            equal = type(observed) is type(value) and observed == value
        if not equal:
            wrong.append(field)
    return {'passed': not wrong, 'wrong_fields': wrong,
            'correct': len(expected)-len(wrong), 'total': len(expected)}

SELECTION_SECTIONS = ('goals', 'decisions', 'constraints', 'artifacts', 'facts',
                      'work_state', 'next_steps', 'permissions')

def fixture_catalog(case):
    """Small eval fixtures only; production catalog/mandatory evidence live in daemon."""
    rows = []
    if case.get('previous_summary'):
        rows.append({'id':'prior', 'role':'memory', 'content':case['previous_summary']})
    rows += [dict(row, id=str(index+1)) for index, row in enumerate(case['messages'])]
    catalog = []
    for row in rows:
        if any(term in row['content'].casefold() for term in
               ('api key', 'api_key', 'apikey', 'password', 'secret', 'mật khẩu', 'token=')):
            continue
        catalog.append(dict(row, selection_id='S'+str(len(catalog)+1)))
    return catalog

def fixture_materialize(output, catalog):
    """Inspect selected texts only; does NOT simulate native mandatory-evidence or budgets."""
    text = output.strip()
    if text.startswith('```json\n') and text.endswith('```'):
        text = text[8:-3]
    root = json.loads(text)
    if not isinstance(root, dict) or root.get('selection_version') != 1 or set(root) != set(SELECTION_SECTIONS) | {'selection_version'}:
        raise ValueError('Invalid selection schema')
    by_id = {row['selection_id']:row for row in catalog}
    selected = []
    seen = set()
    for section in SELECTION_SECTIONS:
        refs = root[section]
        if not isinstance(refs, list) or len(refs) > 64:
            raise ValueError('Invalid selection section: '+section)
        for ref in refs:
            if not isinstance(ref, str) or ref not in by_id:
                raise ValueError('Unknown or invalid selection ID in '+section)
            if ref not in seen:
                selected.append(by_id[ref]['content'])
                seen.add(ref)
    return '\n'.join(selected)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--summaries', type=Path)
    parser.add_argument('--recall-case', type=Path)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--endpoint')
    parser.add_argument('--model')
    parser.add_argument('--output', type=Path, default=Path('/tmp/agenthome-compaction-eval.json'))
    args = parser.parse_args()
    if args.recall_case:
        case = json.loads(args.recall_case.read_text())
        result = score_recall(case['expected_recall'], case['actual_recall'])
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result['passed'] else 1
    cases = json.loads((ROOT/'tests/fixtures/compaction-evals.json').read_text())
    if args.run:
        if not args.endpoint or not args.endpoint.startswith('https://') or not args.model:
            parser.error('--run requires HTTPS --endpoint and --model')
        key = os.environ.get('AGENTHOME_EVAL_API_KEY')
        if not key:
            parser.error('AGENTHOME_EVAL_API_KEY is missing')
        source = (ROOT/'daemon/AHCompactPlan.m').read_text()
        instruction = ast.literal_eval(re.search(r'stringWithFormat:@("(?:[^"\\]|\\.)*")', source).group(1)).replace('%lu', '4096')
        summaries = {}
        opener = urllib.request.build_opener(NoRedirect())
        for case in cases:
            catalog = fixture_catalog(case)
            payload = {'model': args.model, 'max_tokens': 4096, 'stream': False,
                       'messages': [{'role':'system','content':instruction},
                                    {'role':'user','content':json.dumps({'sources':catalog},ensure_ascii=False)}]}
            request = urllib.request.Request(args.endpoint, data=json.dumps(payload).encode(), headers={'Content-Type':'application/json','Authorization':'Bearer '+key})
            with opener.open(request, timeout=180) as response:
                result = json.loads(response.read(2*1024*1024))
            message = result['choices'][0]
            if message.get('finish_reason') not in ('stop', None):
                raise RuntimeError('Incomplete eval response; score not valid')
            summaries[case['id']] = fixture_materialize(message['message']['content'], catalog)
        # Only synthetic fixtures are used; API credentials are never persisted.
        args.output.write_text(json.dumps(summaries,ensure_ascii=False,indent=2)+'\n')
    elif args.summaries:
        summaries = json.loads(args.summaries.read_text())
    else:
        parser.error('Choose --summaries FILE or --run')
    results = [score(case, summaries.get(case['id'], '')) for case in cases]
    print(json.dumps({'kind':('selected source texts only; native evidence/budget validation not executed' if args.run else 'heuristic fact checks; human review still required'),'results':results},ensure_ascii=False,indent=2))
    return 0 if all(result['passed'] for result in results) else 1

if __name__ == '__main__':
    raise SystemExit(main())
