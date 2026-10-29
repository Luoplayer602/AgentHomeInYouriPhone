"""Captured live-model omission plus actual native identifier regex regression."""
import json
from pathlib import Path
# Native evidence extraction is exercised by tests/memory_test.cpp;
# retain the captured 0.11.0 omission as a historical regression fixture.
case=json.loads(Path('tests/fixtures/compaction-live-regression.json').read_text())
missing=[value for value in case['required_identifiers'] if value not in case['summary']]
assert missing==['LOTUS-482']
assert all(value in case['summary']+' Project LOTUS-482' for value in case['required_identifiers'])
print('PASS live regression: captured summary loses LOTUS-482; identifier check detects omission')
