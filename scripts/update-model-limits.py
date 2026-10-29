#!/usr/bin/env python3
"""Reduce a downloaded https://models.dev/api.json to host-scoped token metadata.
Usage: python3 scripts/update-model-limits.py /tmp/models.json
No API keys or user model names are sent to the catalog service.
"""
import json
import sys
from pathlib import Path
source = json.loads(Path(sys.argv[1]).read_text())
hosts = {'api.openai.com': 'openai', 'generativelanguage.googleapis.com': 'google',
         'api.deepseek.com': 'deepseek', 'openrouter.ai': 'openrouter'}
catalog = {}
for host, provider in hosts.items():
    catalog[host] = {}
    for model, info in source[provider]['models'].items():
        limit = info.get('limit', {})
        if limit.get('context', 0) < 1024:
            continue
        catalog[host][model] = {'window_tokens': limit['context'],
                               'max_input_tokens': limit.get('input', 0),
                               'model_output_tokens': limit.get('output', 0)}
Path('layout/usr/share/agenthome/model-limits.json').write_text(
    json.dumps(catalog, ensure_ascii=False, separators=(',', ':')) + '\n')
