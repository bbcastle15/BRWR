#!/usr/bin/env python3
"""Read-only forensic audit of failed game 198, event 5 at step 151.

Does not train, invoke Godot, load untrusted pickle, or modify episode/receipts.
It writes a compact report to the BRWR project root.
"""
import collections
import datetime
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATASETS = ROOT / 'ai' / 'datasets'
GLOB = 'v5_semantic_episode_20350299_*.jsonl'
REPORT = ROOT / 'v5m1_game198_attribution_diagnostic.txt'
TARGET_STEP = 151
TARGET_EVENT_IX = 5  # Python enumerates events from zero.

out = []
def say(s=''):
    out.append(str(s))

def pretty(x, limit=14000):
    try:
        s = json.dumps(x, ensure_ascii=False, indent=2, default=str)
    except Exception:
        s = repr(x)
    return s if len(s) <= limit else s[:limit] + '\n... [truncated]'

def selected_candidate(t):
    options = t.get('legal_candidates')
    idx = t.get('selected_candidate_id')
    if not isinstance(options, list) or not isinstance(idx, int) or not (0 <= idx < len(options)):
        return None
    return options[idx]

def selected_spell(t):
    c = selected_candidate(t)
    if not isinstance(c, dict):
        return None
    d = c.get('detail', {})
    if not isinstance(d, dict):
        return None
    desc = d.get('descriptor', {})
    if not isinstance(desc, dict):
        return None
    a = d.get('action', {})
    if not isinstance(a, dict):
        return None
    if desc.get('kind') != 'cast' and a.get('type') not in ('spell', 'quick'):
        return None
    spell = desc.get('spell')
    if not isinstance(spell, dict):
        return None
    return spell

def concise(t):
    c = selected_candidate(t)
    d = c.get('detail', {}) if isinstance(c, dict) else {}
    desc = d.get('descriptor', {}) if isinstance(d, dict) else {}
    return {
        'step':t.get('step'), 'player_index':t.get('player_index'),
        'request_type':t.get('request_type'), 'selected_candidate_id':t.get('selected_candidate_id'),
        'selected_candidate':c,
        'candidate_count':len(t.get('legal_candidates', [])) if isinstance(t.get('legal_candidates'), list) else None,
    }

def main():
    say('V5M1 Game 198 receipt identity mismatch diagnostic')
    say('Generated: '+datetime.datetime.now().isoformat(timespec='seconds'))
    say('READ ONLY for all project model, training, episode and receipt files.')
    say('Expected game=198 seed=20350299 event index=5 (sixth), step=151')
    say()
    matches = sorted(DATASETS.glob(GLOB), key=lambda x:x.stat().st_mtime, reverse=True)
    if not matches:
        say('EPISODE NOT FOUND: '+str(DATASETS / GLOB))
        say('Look in ai/datasets/replaced_before_v5_training or restore a copy of this episode without overwriting newer data.')
        REPORT.write_text('\n'.join(out)+'\n',encoding='utf-8')
        print('V5M1_GAME198_DIAGNOSTIC_SAVED '+str(REPORT))
        return
    if len(matches)>1:
        say('WARNING: multiple matching episodes: '+repr([p.name for p in matches]))
    episode=matches[0]
    receipts=Path(str(episode)+'.r3_receipts.json')
    say('EPISODE '+str(episode)+' bytes='+str(episode.stat().st_size)+' modified='+str(datetime.datetime.fromtimestamp(episode.stat().st_mtime)))
    transitions=[]
    record_types=collections.Counter()
    bad_lines=[]
    with episode.open(encoding='utf-8') as f:
        for line_num,line in enumerate(f,1):
            if not line.strip(): continue
            try: r=json.loads(line)
            except Exception as e:
                bad_lines.append([line_num,str(e)]); continue
            if not isinstance(r,dict): continue
            record_types[r.get('record_type','<none>')]+=1
            if r.get('record_type')=='transition': transitions.append(r)
    say('RECORD_TYPES '+pretty(record_types))
    say('TRANSITIONS '+str(len(transitions))+' BAD_LINES '+pretty(bad_lines[:10]))
    if not receipts.exists():
        say('RECEIPTS NOT FOUND: '+str(receipts))
        REPORT.write_text('\n'.join(out)+'\n',encoding='utf-8')
        print('V5M1_GAME198_DIAGNOSTIC_SAVED '+str(REPORT))
        return
    data=json.loads(receipts.read_text(encoding='utf-8'))
    events=data.get('events',[]) if isinstance(data,dict) else []
    say('RECEIPTS '+str(receipts)+' bytes='+str(receipts.stat().st_size))
    say('RECEIPT_HEADER '+pretty({k:v for k,v in data.items() if k!='events'}))
    say('RECEIPT_COUNT '+str(len(events)))
    say()
    for i in [TARGET_EVENT_IX-1,TARGET_EVENT_IX,TARGET_EVENT_IX+1]:
        if 0 <= i < len(events):
            say('RECEIPT events[%d] (human event #%d):\n%s'%(i,i+1,pretty(events[i])))
    event = events[TARGET_EVENT_IX] if len(events)>TARGET_EVENT_IX else {}
    target_spell=event.get('spell_id') if isinstance(event,dict) else None
    target_player=event.get('player_index') if isinstance(event,dict) else None
    target_step=event.get('step') if isinstance(event,dict) else TARGET_STEP
    say()
    say('STEP 151 / around relevant receipt step:')
    for i in range(max(1,TARGET_STEP-4),min(len(transitions),TARGET_STEP+4)+1):
        say('STEP %d %s'%(i,pretty(concise(transitions[i-1]),3500)))
    if isinstance(target_step,int) and target_step!=TARGET_STEP and 1<=target_step<=len(transitions):
        say('RECEIPT CLAIMS DIFFERENT STEP; actual source: '+pretty(concise(transitions[target_step-1])))
    say()
    say('SELECTED CASTS FOR THE SAME PLAYER AND SAME SPELL (all episode):')
    found=[]
    for i,t in enumerate(transitions,1):
        if t.get('player_index')==target_player:
            spell=selected_spell(t)
            if isinstance(spell,dict) and spell.get('id')==target_spell:
                found.append((i,t))
    say('matching_count='+str(len(found)))
    for i,t in found[:30]: say('STEP %d %s'%(i,pretty(concise(t),4500)))
    say()
    say('OTHER CASTS BY SAME PLAYER NEAR TARGET STEP (last 25):')
    same=[]
    for i,t in enumerate(transitions,1):
        if i>target_step or t.get('player_index')!=target_player: continue
        spell=selected_spell(t)
        if spell: same.append((i,t))
    for i,t in same[-25:]:
        s=selected_spell(t)
        say('step=%d spell=%s side=%s candidate_id=%s'%(i,s.get('id'),('DARK' if s.get('use_dark_side') is True else 'LIGHT' if s.get('use_dark_side') is False else 'UNKNOWN'),t.get('selected_candidate_id')))
    say()
    say('ALL RECEIPTS OF SAME SPELL, SAME PLAYER, OR SAME STEP:')
    for i,e in enumerate(events):
        if isinstance(e,dict) and (e.get('spell_id')==target_spell or e.get('player_index')==target_player or e.get('step')==TARGET_STEP):
            say('events[%d] %s'%(i,pretty(e,2000)))
    say()
    validator=ROOT/'ai/python/v5m1_effect_receipts.py'
    if validator.exists():
        lines=validator.read_text(encoding='utf-8').splitlines()
        indices=[i for i,line in enumerate(lines) if 'direct-cast spell identity mismatch' in line]
        for index in indices:
            say('VALIDATOR EXCERPT:')
            for j in range(max(0,index-25),min(len(lines),index+8)):
                say('%3d | %s'%(j+1,lines[j]))
    say('END. No training or checkpoint modifications.')
    REPORT.write_text('\n'.join(out)+'\n',encoding='utf-8')
    print('V5M1_GAME198_DIAGNOSTIC_SAVED '+str(REPORT))
    print('RECEIPT_5 spell=%s player=%s step=%s origin=%s kind=%s'%(
        target_spell,target_player,target_step,event.get('cast_origin') if isinstance(event,dict) else None,event.get('kind') if isinstance(event,dict) else None))
    if 1<=TARGET_STEP<=len(transitions):
        spell=selected_spell(transitions[TARGET_STEP-1])
        print('STEP_151_SELECTED_CAST '+(pretty(spell,700) if spell else '(not a direct selected cast)'))
    print('MATCHING_SELECTED_CASTS '+str(len(found)))
    print('READ_ONLY_OK')

if __name__=='__main__': main()
