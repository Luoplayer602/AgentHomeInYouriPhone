"""Captured live-model omission plus actual native identifier regex regression."""
import json
import re
from pathlib import Path
source=Path('daemon/AHCompactPlan.m').read_text()
pattern=re.search(r'regularExpressionWithPattern:@"([^"\n]+)"',source).group(1)
regex=re.compile(pattern)
assert regex.findall('Project LOTUS-482, ticket T-42; reference AB-1234.')==['LOTUS-482','T-42','AB-1234']
assert not regex.findall('prefixLOTUS-482suffix abc-123 TEST_SECRET_NEVER_INCLUDE_7')
assert not regex.findall('ABC-12-34')
case=json.loads(Path('tests/fixtures/compaction-live-regression.json').read_text())
missing=[value for value in case['required_identifiers'] if value not in case['summary']]
assert missing==['LOTUS-482']
assert all(value in case['summary']+' Project LOTUS-482' for value in case['required_identifiers'])
print('PASS live regression: captured summary loses LOTUS-482; identifier check detects omission; single-letter ticket and boundary cases')
