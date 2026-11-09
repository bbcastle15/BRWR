"""Compare two native Godot JSONL episodes for identical setup and decisions."""
from pathlib import Path
import hashlib
import json
import sys

if len(sys.argv) != 3:
    sys.exit('Usage: python check_school_cache_parity.py baseline.jsonl cached.jsonl')

def digest(path):
    data = {'start': None, 'end': None, 'sequence': []}
    with Path(path).open(encoding='utf-8') as f:
        for line in f:
            entry = json.loads(line)
            typ = entry.get('record_type')
            if typ == 'episode_start':
                data['start'] = {'seed':entry.get('seed'), 'active_schools':entry.get('active_schools'),
                                 'player_count':entry.get('player_count'), 'avatar_id':entry.get('avatar_id')}
            elif typ == 'episode_end':
                data['end'] = {k:entry.get(k) for k in ('seed','winner','scores','round','decisions')}
            elif typ == 'transition':
                data['sequence'].append((entry.get('player_index'),entry.get('request_type'),
                    entry.get('substep'),entry.get('selected_candidate_id')))
    if data['start'] is None or data['end'] is None or not data['sequence']:
        sys.exit('SCHOOL_CACHE_PARITY_FAIL incomplete episode ' + str(path))
    return data

first = digest(sys.argv[1]); second = digest(sys.argv[2])
problems=[]
for k in ('start','end','sequence'):
    if first[k] != second[k]:
        problems.append(k)
        print('SCHOOL_CACHE_DIFFERENCE',k)
        if k == 'start': print(' baseline=',first[k], '\n cached=',second[k])
        elif k == 'end': print(' baseline=',first[k], '\n cached=',second[k])
        else:
            for i,(a,b) in enumerate(zip(first[k],second[k])):
                if a!=b:
                    print(f' first differing transition at {i+1}: baseline={a} cache={b}')
                    break
            print(' transition counts',len(first[k]),len(second[k]))
if problems:
    sys.exit('SCHOOL_CACHE_PARITY_FAIL fields=' + ','.join(problems))
print(f'SCHOOL_CACHE_PARITY_OK decisions={len(first["sequence"])} active_schools={first["start"]["active_schools"]} winner={first["end"]["winner"]}')
