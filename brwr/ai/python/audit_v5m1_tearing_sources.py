#!/usr/bin/env python3
"""Read-only BRWR R3 Tearing provenance and source audit.

Reads existing episode+receipts, actual spell definitions, and source files.
Writes only an audit report and a small evidence ZIP in the repository root.
Never imports the trainer, runs Godot, resets checkpoints, or edits the Game.
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import datetime as dt
import json
from pathlib import Path
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
EPISODE = ROOT / 'ai/datasets/v5_semantic_episode_20350232_h5_avpossessed_apprentice_normal.jsonl'
RECEIPT = Path(str(EPISODE) + '.r3_receipts.json')
OUTPUT = ROOT / 'v5m1_tearing_source_audit.txt'
BUNDLE = ROOT / 'v5m1_tearing_evidence_bundle.zip'
SOURCE_PATHS = [
    'build_v5_r3_effect_receipts.py',
    'r3_game_effect_methods.gd.inc',
    'ai/python/v5_r3_effect_receipts.py',
    'ai/ai_policy_school_v5_match.gd',
    'ai/python/train_v5_momentumone_reset.py',
]
SOURCE_INSPECT = [
    'ai/game_school_cached.gd',
    'ai/ai_policy_school_v5_match.gd',
    'build_v5_r3_effect_receipts.py',
    'r3_game_effect_methods.gd.inc',
]
# Probe both emission and spell execution code, not merely the validator.
PATTERN = re.compile(r'(?i)\br3\b|_r3_|receipt|source[_ ]step|spell[_ ]context|last[_ ]spell|effect[_ ]receipt|spell[_ ]effect')


def dump(obj, lim=1800):
    out = json.dumps(obj, indent=2, ensure_ascii=False, default=str)
    return out if len(out) <= lim else out[:lim] + '\n...[truncated]'


def selected_action(t):
    if not isinstance(t, dict):
        return {}
    selected_id = t.get('selected_candidate_id')
    choices = t.get('legal_candidates') or []
    candidates = [c for c in choices if isinstance(c, dict) and c.get('id') == selected_id]
    if len(candidates) != 1:
        return {'id': selected_id, 'problem': 'selected candidate not unique', 'matching_count': len(candidates)}
    c = candidates[0]
    detail = c.get('detail') or {}
    desc = detail.get('descriptor') or {}
    spell = desc.get('spell') or {}
    return {
        'id': selected_id,
        'label': c.get('label'),
        'candidate_kind': detail.get('kind'),
        'action_kind': desc.get('kind'),
        'spell_id': spell.get('id'),
        'side': ('Dark' if spell.get('use_dark_side') is True else 'Light' if spell.get('use_dark_side') is False else None),
        'spell_type': desc.get('spell_type'),
        'action_type': (detail.get('action') or {}).get('type'),
        'destination': (desc.get('action') or {}).get('destination_room_ids'),
        'room_activation_timing': desc.get('room_activation_timing'),
        'selected_detail': desc if t.get('step') in (87, 416, 417) else None,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--episode', default=str(EPISODE))
    ap.add_argument('--audit-history', action='store_true', help='Read all previous 2035 episodes (~4.6 GB), no writes')
    args = ap.parse_args()
    ep = Path(args.episode)
    rc = Path(str(ep) + '.r3_receipts.json')
    lines = []
    def say(s=''): lines.append(str(s))
    say('BRWR V5M1 | Tearing / R3 reward provenance audit')
    say('Created: '+dt.datetime.now().isoformat(timespec='seconds'))
    say('READ ONLY INPUTS. Does not run or modify checkpoints, episodes or source.')
    say('Episode: '+str(ep))
    if not ep.exists():
        say('EPISODE_NOT_FOUND')
    if not rc.exists():
        say('RECEIPTS_NOT_FOUND')
    transitions=[]
    non_transition=[]
    if ep.is_file():
        with ep.open('r',encoding='utf-8') as f:
            for lineno,line in enumerate(f, 1):
                if not line.strip(): continue
                try: obj=json.loads(line)
                except Exception as e:
                    say(f'BAD_EPISODE_JSON line={lineno} error={e}')
                    continue
                if not isinstance(obj,dict): continue
                if obj.get('record_type') == 'transition':
                    transitions.append(obj)
                else:
                    non_transition.append((lineno, list(obj.keys()), obj.get('record_type')))
    say(f'EPISODE_TRANSITIONS={len(transitions)} NON_TRANSITIONS={non_transition[:20]}')
    casts=[]
    for t in transitions:
        a=selected_action(t)
        if a.get('action_kind') == 'cast':
            casts.append({'step':t.get('step'),'owner':t.get('player_index'),
                          'spell':a.get('spell_id'),'side':a.get('side'),'label':a.get('label')})
    say('\nTEARING CASTS (ALL players, sides):')
    for c in casts:
        if c['spell'] == 'tearing': say('  '+dump(c))
    say('\nPLAYER 3 CASTS BEFORE STEP 416:')
    for c in casts:
        if c['owner']==3 and (c['step'] or 0) <= 416: say('  '+dump(c))
    say('\nTIMELINE around first Tearing / step 416:')
    for t in transitions:
        step=t.get('step',0)
        if 82 <= step <= 95 or 409 <= step <= 423:
            say('  step=%r owner=%r request=%s => %s' % (step,t.get('player_index'),t.get('request_type'),dump(selected_action(t),1400)))
    if rc.is_file():
        try:
            r=json.loads(rc.read_text(encoding='utf-8'))
        except Exception as e:
            r={}; say('BAD_RECEIPTS_JSON '+repr(e))
        say('\nRECEIPT SCHEMA '+dump({k:v for k,v in r.items() if k!='events'},1500))
        events=r.get('events',[])
        mismatches=[]
        for ix,e in enumerate(events):
            step=e.get('step')
            if isinstance(step,int) and 1<=step<=len(transitions):
                t=transitions[step-1]
                a=selected_action(t)
                same_owner=t.get('player_index')==e.get('player_index')
                same_spell=a.get('spell_id')==e.get('spell_id')
                valid=same_owner and same_spell and a.get('action_kind')=='cast'
            else:
                a={}; same_owner=False; same_spell=False; valid=False
            if not valid:
                recent=[c for c in casts if c['owner']==e.get('player_index') and c['spell']==e.get('spell_id') and (c['step'] or 0)<=step]
                mismatches.append(ix)
                say('MISMATCH event_index_zero_based=%d => %s\n  actual_selected=%s\n  matching_casts_before=%s' %
                    (ix,dump(e,1200),dump(a,1000),dump(recent[-10:],1000)))
        say('\nRECEIPT COUNTS total=%d mismatches=%d indexes=%s' % (len(events),len(mismatches),mismatches))
        say('TEARING RECEIPT EVENTS:')
        for i,e in enumerate(events):
            if e.get('spell_id')=='tearing':say('  '+dump({'index':i,**e},1500))
    if args.audit_history:
        say('\nHISTORICAL RECEIPT PROVENANCE AUDIT (ALL AVAILABLE 2035 EPISODES):')
        reviewed = 0
        invalid_total = 0
        cast_mismatch_total = 0
        missing_receipts = 0
        for old_episode in sorted(ep.parent.glob('v5_semantic_episode_2035*.jsonl')):
            old_receipt = Path(str(old_episode) + '.r3_receipts.json')
            if not old_receipt.is_file():
                missing_receipts += 1
                continue
            try:
                old_r = json.loads(old_receipt.read_text(encoding='utf-8'))
                evs = old_r.get('events', [])
                relevant = {int(e.get('step', -1)) for e in evs if isinstance(e, dict)}
                observed = {}
                with old_episode.open('r', encoding='utf-8') as fd:
                    for row in fd:
                        if not row.strip(): continue
                        t = json.loads(row)
                        if isinstance(t,dict) and t.get('record_type')=='transition' and t.get('step') in relevant:
                            observed[t['step']] = (t.get('player_index'), selected_action(t))
                bad=[]
                for ix,e in enumerate(evs):
                    owner, act = observed.get(e.get('step'), (None,{}))
                    if (owner != e.get('player_index') or act.get('action_kind') != 'cast' or
                            act.get('spell_id') != e.get('spell_id')):
                        bad.append((ix, e.get('spell_id'), e.get('step'), act.get('spell_id'), act.get('action_kind')))
                        if owner == e.get('player_index') and act.get('action_kind') == 'cast':
                            cast_mismatch_total += 1
                reviewed += 1
                invalid_total += len(bad)
                if bad:
                    say('  episode=%s events=%d BAD=%d first_bad=%s' %
                        (old_episode.name,len(evs),len(bad),dump(bad[:12],1600)))
            except Exception as exc:
                say('  EPISODE_AUDIT_ERROR %s %s: %s' % (old_episode.name,type(exc).__name__,exc))
        say('  HISTORY_SUMMARY episodes_reviewed=%d provenance_invalid=%d wrong_spell_but_other_cast=%d missing_receipt_files=%d' %
            (reviewed,invalid_total,cast_mismatch_total,missing_receipts))
    say('\nSPELL DEFINITION (CURRENT LOCAL FILE):')
    searched=[]
    candidates=[ROOT/'data/spells.json',ROOT/'spells.json',ROOT/'brwr/data/spells.json']
    candidates += list((ROOT/'data').glob('**/spells.json')) if (ROOT/'data').is_dir() else []
    seen=set()
    for p in candidates:
        if p in seen: continue
        seen.add(p)
        if not p.is_file(): continue
        searched.append(str(p.relative_to(ROOT)))
        try:
            doc=json.loads(p.read_text(encoding='utf-8-sig'))
            if isinstance(doc,list): variants=[x for x in doc if isinstance(x,dict) and x.get('id')=='tearing']
            elif isinstance(doc,dict):
                variants=[]
                def visit(o):
                    if isinstance(o,dict):
                        if o.get('id')=='tearing': variants.append(o)
                        for v in o.values(): visit(v)
                    if isinstance(o,list):
                        for v in o: visit(v)
                visit(doc)
            else: variants=[]
            for v in variants:say('  '+str(p.relative_to(ROOT))+' => '+dump(v,2500))
        except Exception as e:say('  ERROR reading '+str(p)+' '+str(e))
    say('  searched='+dump(searched))
    say('\nSOURCE LOCATIONS (exact lines, focus on effect crediting and context):')
    excerpts=[]
    for rel in SOURCE_INSPECT:
        p=ROOT/rel
        if not p.is_file():
            say('  MISSING '+rel)
            continue
        content=p.read_text(encoding='utf-8-sig',errors='replace').splitlines()
        match_idxs=[i for i,l in enumerate(content) if PATTERN.search(l)]
        say(f'  {rel} total_lines={len(content)} matching_lines={len(match_idxs)}')
        # Cover complete smaller sources; show only sparse relevant hits for massive generated game.
        if rel.startswith('ai/game_school_cached.gd'):
            important=[i for i in match_idxs if re.search(r'(?i)receipt|_r3_|r3_|spell[_ ]context|source[_ ]step',content[i])]
            chosen=important[:65]
        elif rel.endswith('.gd.inc') or rel.startswith('build_v5_r3'):
            chosen=match_idxs[:85]
        else:
            chosen=match_idxs[:40]
        windows=[]
        for i in chosen:
            lo=max(0,i-4); hi=min(len(content),i+5)
            if windows and lo<=windows[-1][1]:windows[-1]=(windows[-1][0],max(windows[-1][1],hi))
            else: windows.append((lo,hi))
        for lo,hi in windows:
            for j in range(lo,hi):
                excerpts.append(f'    {rel}:{j+1:05d} {content[j]}')
            excerpts.append('    ---')
    say('\n'.join(excerpts[:1400]))
    say('\nEND OF READ-ONLY AUDIT')
    OUTPUT.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    # Small evidence archive; no checkpoint, full episode, or huge generated Game.
    included=[]
    with zipfile.ZipFile(BUNDLE,'w',zipfile.ZIP_DEFLATED, compresslevel=8) as z:
        z.write(OUTPUT,OUTPUT.name)
        for rel in SOURCE_PATHS:
            p=ROOT/rel
            if p.is_file() and p.stat().st_size <= 512*1024:
                z.write(p,rel)
                included.append(rel)
    print('TEARING_AUDIT_REPORT '+str(OUTPUT))
    print('TEARING_EVIDENCE_ZIP '+str(BUNDLE))
    print('SOURCES_INCLUDED '+','.join(included))
    print('CHECKPOINT_AND_GAME_UNCHANGED=1')

if __name__ == '__main__': main()
