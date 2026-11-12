#!/usr/bin/env python3
"""Read-only summary of actual, attributed R3 spell receipts."""
import argparse
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('episode', nargs='?', help='Existing R3 episode JSONL (optional: most recent)')
    args=ap.parse_args()
    if args.episode:
        episode=Path(args.episode)
    else:
        candidates=sorted((ROOT/'ai/datasets').glob('v5_semantic_episode_*.jsonl.r3_receipts.json'), key=lambda p:p.stat().st_mtime)
        if not candidates: raise RuntimeError('No saved R3 receipt file. Run -Games 1 -KeepEpisodes first')
        receipt=candidates[-1]
        episode=Path(str(receipt).removesuffix('.r3_receipts.json'))
    receipt=Path(str(episode)+'.r3_receipts.json')
    if not episode.is_file() or not receipt.is_file(): raise RuntimeError('Missing episode or receipt file')
    doc=json.loads(receipt.read_text(encoding='utf-8'))
    expected=0
    casts={}
    for line in episode.open(encoding='utf-8'):
        row=json.loads(line)
        if row.get('record_type')=='transition':
            expected+=1
            ix=int(row['selected_candidate_id'])
            c=row['legal_candidates'][ix]
            casts[expected]=(int(row['player_index']), str(c.get('label','')))
    if doc.get('schema')!='brwr_v5_r3_effect_receipts_v1' or doc.get('decisions')!=expected:
        raise RuntimeError('Receipt schema or transition count mismatch')
    print('R3_EFFECTS_AUDIT seed=%s decisions=%d successful_resolutions=%d uncredited=%s' %
          (doc['seed'], expected, len(doc.get('events',[])), doc.get('uncredited')))
    for ev in doc.get('events',[]):
        step=int(ev['step']); owner=int(ev['player_index'])
        if step not in casts or casts[step][0]!=owner: raise RuntimeError('Wrong player/step attribution at '+str(step))
        print('  step=%-4d mage=%d kind=%-8s spell=%-28s concrete_state_delta=%s prevented=%s' %
              (step,owner+1,ev['kind'],ev['spell_id'],ev['material_change'],ev['prevention']))
    print('R3_EFFECTS_AUDIT_COMPLETE read_only=1')

if __name__=='__main__': main()
