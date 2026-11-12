#!/usr/bin/env python3
"""Read-only BRWR V5M1 game 399 R3 receipt identity/reaction-choice forensic diagnostic.

Reads episode and receipt JSONL/JSON from local project. Never loads checkpoints,
imports the game, rewrites episode/history, or executes training. Outputs a small
text report and zip containing evidence + relevant code (not the large JSONL).
"""
from __future__ import annotations

import collections
import csv
from datetime import datetime
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'ai' / 'datasets'
GAME = 399
SEED = 20350500
EVENT_INDEX = 7
EXPECTED_STEP = 157
REPORT = ROOT / 'v5m1_game399_attribution_diagnostic.txt'
BUNDLE = ROOT / 'v5m1_game399_evidence_bundle.zip'
LOGS = DATA / 'v5m1_run_logs'


def pretty(o, limit=9000):
    try:
        result = json.dumps(o, ensure_ascii=False, indent=2, default=str)
    except (TypeError, ValueError):
        result = repr(o)
    if len(result) > limit:
        return result[:limit] + '\n... [truncated]'
    return result


def chosen(t):
    options = t.get('legal_candidates')
    selected = t.get('selected_candidate_id')
    if not isinstance(options, list) or not isinstance(selected, int) or not 0 <= selected < len(options):
        return None
    candidate = options[selected]
    return candidate if isinstance(candidate, dict) else None


def summarize(t):
    c = chosen(t)
    d = c.get('detail', {}) if c else {}
    d = d if isinstance(d, dict) else {}
    desc = d.get('descriptor', {})
    desc = desc if isinstance(desc, dict) else {}
    action = d.get('action', {})
    action = action if isinstance(action, dict) else {}
    spell = desc.get('spell', {})
    spell = spell if isinstance(spell, dict) else {}
    payload = c.get('payload') if c else None
    detail_fields = {}
    for k in ('id', 'name', 'card_kind', 'board_player_index', 'selected_count',
              'token', 'target_type', 'player_index', 'room_id', 'slot_id'):
        if k in d:
            detail_fields[k] = d[k]
    action_fields = {k: action.get(k) for k in ('type', 'activate_room_after_movement',
                     'activate_room_before_movement', 'perform_room_activation',
                     'destination_room_ids') if k in action}
    return {
        'step': t.get('step'), 'player_index': t.get('player_index'),
        'request_type': t.get('request_type'), 'candidate_index': t.get('selected_candidate_id'),
        'label': c.get('label') if c else None, 'detail': detail_fields,
        'descriptor_kind': desc.get('kind'), 'spell_id': spell.get('id'),
        'use_dark_side': spell.get('use_dark_side'), 'action': action_fields,
        'path': desc.get('path'), 'final_room_id': desc.get('final_room_id'),
        'room_activation_timing': desc.get('room_activation_timing'),
        'payload': payload,
        'candidate_count': len(t.get('legal_candidates', [])) if isinstance(t.get('legal_candidates'), list) else None,
    }


def select_spells(t):
    """Extract spell identity from a direct cast or arm-card selection."""
    s = summarize(t)
    return s.get('spell_id') or (s['detail'].get('id') if s['detail'].get('card_kind') == 'spells' else None)


def main():
    lines = []
    out = lambda x='': lines.append(str(x))
    out('BRWR V5-MOMENTUM-ONE | game 399 attribution forensic audit')
    out('READ ONLY for model, optimizer, checkpoint, training history, episodes, receipts, sources.')
    out('Created ' + datetime.now().isoformat(timespec='seconds'))
    out(f'Expected game={GAME} seed={SEED} event_index={EVENT_INDEX} step={EXPECTED_STEP}')
    out('')

    ep = sorted(DATA.glob(f'v5_semantic_episode_{SEED}_*.jsonl'),
                key=lambda p: p.stat().st_mtime, reverse=True)
    if len(ep) != 1:
        out(f'EPISODE_MATCHES={len(ep)}: {pretty([str(p) for p in ep])}')
    if not ep:
        out('ERROR: Missing failed episode in ai/datasets. DO NOT rerun training just to produce a new episode.')
        report_and_bundle(lines, None, None, [])
        return 2
    episode = ep[0]
    rec_path = Path(str(episode) + '.r3_receipts.json')
    out(f'EPISODE {episode} bytes={episode.stat().st_size}')
    transitions = []
    types = collections.Counter()
    bad = []
    tail = None
    with episode.open('r', encoding='utf-8') as fh:
        for line_no, ln in enumerate(fh, 1):
            if not ln.strip():
                continue
            try:
                record = json.loads(ln)
            except (ValueError, UnicodeDecodeError) as exc:
                bad.append((line_no, str(exc)))
                continue
            if not isinstance(record, dict):
                continue
            typ = record.get('record_type')
            types[str(typ)] += 1
            if typ == 'transition':
                transitions.append(record)
            elif typ == 'episode_end':
                tail = record
    out('RECORD_TYPES ' + pretty(types))
    out(f'TRANSITIONS={len(transitions)} parse_errors={pretty(bad[:10])}')
    if tail is not None:
        out('EPISODE_END ' + pretty(tail, 2000))
    if not rec_path.exists():
        out('ERROR: Receipt file missing: ' + str(rec_path))
        report_and_bundle(lines, episode, None, [])
        return 2
    try:
        doc = json.loads(rec_path.read_text(encoding='utf-8'))
    except (ValueError, UnicodeDecodeError) as exc:
        out('ERROR: Receipt JSON invalid: ' + str(exc))
        report_and_bundle(lines, episode, None, [])
        return 2
    events = doc.get('events') if isinstance(doc, dict) else []
    if not isinstance(events, list):
        events = []
    out(f'RECEIPT_PATH {rec_path} bytes={rec_path.stat().st_size}')
    out('RECEIPT_HEADER '+pretty({k:v for k,v in doc.items() if k != 'events'} if isinstance(doc,dict) else doc, 2500))
    out('RECEIPT_COUNT='+str(len(events)))
    out('')

    event = events[EVENT_INDEX] if len(events) > EVENT_INDEX and isinstance(events[EVENT_INDEX], dict) else {}
    out(f'TARGET events[{EVENT_INDEX}] '+pretty(event))
    step = event.get('step')
    owner = event.get('player_index')
    spell = event.get('spell_id')
    if not isinstance(step, int):
        step = EXPECTED_STEP
    if 1 <= step <= len(transitions):
        rec = transitions[step - 1]
        out('CLAIMED_STEP_SELECTED '+pretty(summarize(rec)))
        out('CLAIMED_STEP_RAW_SELECTED '+pretty(chosen(rec), 5000))
        out('STEP_OWNER_MATCH='+str(rec.get('player_index') == owner))
    else:
        out('CLAIMED_STEP_OUT_OF_RANGE')
    out('')
    out('RECEIPTS SURROUNDING TARGET (including other players):')
    for ix in range(max(0, EVENT_INDEX-6), min(len(events), EVENT_INDEX+7)):
        out('events[%d] %s'%(ix, pretty(events[ix], 2500)))
    out('')

    out('TARGET REACTION / CAST EVIDENCE:')
    if 1 <= step <= len(transitions):
        for n in range(max(1,step-3), min(len(transitions),step+2)+1):
            record=transitions[n-1]
            out(f'STEP {n} SELECTED '+pretty(summarize(record),2500))
            if n in (step,step-1):
                out('RAW_CHOICE '+pretty(chosen(record),4500))
    out('OTHER RECEIPTS FOR SAME SPELL:')
    out(pretty([{'index':ix,**e} for ix,e in enumerate(events)
        if isinstance(e,dict) and e.get('spell_id') == spell],5000))
    out('TRIGGER / REACTION AVAILABLE-CHOICE WINDOW:')
    for n in range(max(1,step-12),min(len(transitions),step+8)+1):
        record=transitions[n-1]
        if record.get('request_type') != 'effect_choice':
            continue
        choices=record.get('legal_candidates')
        if not isinstance(choices,list):
            continue
        hits=[]
        for idx,c in enumerate(choices):
            if not isinstance(c,dict):
                continue
            detail=c.get('detail',{})
            if not isinstance(detail,dict):
                detail={}
            label=str(c.get('label',''))
            if (detail.get('id') == spell or
                any(kw in label.lower() for kw in ('trigger','confirm','select ','pass','cancel'))):
                hits.append({'index':idx,'label':label,'detail':
                    {key:detail.get(key) for key in ('id','card_kind','board_player_index','selected_count') if key in detail}})
        if hits:
            out(f'STEP {n} PLAYER {record.get("player_index")} CHOSEN {record.get("selected_candidate_id")}: '+pretty(hits[:20],4000))
    out('')
    out('ALL STEP/OWNER MISMATCHES:')
    mismatches = []
    for ix, e in enumerate(events):
        if not isinstance(e, dict):
            mismatches.append([ix,'non_dict'])
            continue
        s, p = e.get('step'), e.get('player_index')
        if not isinstance(s, int) or not (1 <= s <= len(transitions)):
            mismatches.append([ix,'out_of_range',s,p])
        elif transitions[s-1].get('step') != s or transitions[s-1].get('player_index') != p:
            mismatches.append([ix,'different_source',s,p,transitions[s-1].get('player_index'),e.get('spell_id'),e.get('kind')])
    out(pretty(mismatches))
    out('')
    out('TIMELINE surrounding claimed step (selected choices):')
    neighbors = []
    for k in range(max(1, step-18), min(len(transitions), step+14)+1):
        entry = summarize(transitions[k-1])
        neighbors.append(entry)
        out('STEP %d %s'%(k,pretty(entry,1500)))
    out('')
    out('NEARBY ACTIONS BY RECEIPT OWNER AND STEP OWNER (last 25 before / 15 after):')
    step_owner = transitions[step-1].get('player_index') if 1 <= step <= len(transitions) else None
    for p in (owner, step_owner):
        if p is None:
            continue
        out('PLAYER '+str(p))
        data = [(i,summarize(t)) for i,t in enumerate(transitions,1)
                if t.get('player_index') == p
                and (i <= step and i >= max(1,step-150) or step < i <= step+15)]
        for i,s in data[-50:]:
            out('STEP %d %s'%(i,pretty(s,1200)))
    out('')
    out('MATCHING SPELL CASTS / CARD CHOICES ACROSS THE ENTIRE EPISODE:')
    matching=[]
    for i,t in enumerate(transitions,1):
        if spell and select_spells(t) == spell:
            matching.append(summarize(t))
    out(pretty(matching[:80],16000))
    out('')
    out('ALL RECEIPTS SAME OWNER / SPELL / STEP:')
    for ix,e in enumerate(events):
        if isinstance(e,dict) and (e.get('player_index') == owner or e.get('spell_id') == spell or e.get('step') == step):
            out('events[%d] %s'%(ix,pretty(e,1100)))

    history = ROOT/'ai/model/training_history_v5_momentumone_reset.csv'
    if history.exists():
        try:
            with history.open(encoding='utf-8-sig',newline='') as fh:
                csvreader = csv.DictReader(fh)
                last=None
                n=0
                for row in csvreader:
                    n+=1
                    last=row
            out('HISTORY rows=%d last_game=%s'%(n,last.get('v5m1_game') if last else '<none>'))
        except (OSError, ValueError) as exc:
            out('HISTORY read issue: '+str(exc))

    out('')
    out('RECEIPT EMISSION / VALIDATOR RELEVANT LINES:')
    for relative, patterns in [
        ('r3_game_effect_methods.gd.inc',('_brwr_r3_emit','_brwr_r3_cast_decision','caster_id')),
        ('build_v5_r3_effect_receipts.py',('_brwr_r3_cast_decision','_brwr_r3_decision_step','process_trigger_spell_resolution')),
        ('build_v5m1_roomcast_provenance.py',('room_cast_next_ready','_brwr_r3_cast_decision','cast_origin')),
        ('ai/python/v5m1_effect_receipts.py',('step/owner attribution invalid','_reaction_card_selection_step','_direct_cast_matches','no verified reaction selection')),
    ]:
        path=ROOT/relative
        if path.exists():
            s=path.read_text(encoding='utf-8-sig',errors='replace').splitlines()
            indices=[k for k,v in enumerate(s) if any(w in v for w in patterns)]
            out('SOURCE '+relative+' hits='+str(len(indices)))
            included=set()
            for k in indices[:15]:
                for j in range(max(0,k-2),min(len(s),k+4)):
                    if j not in included:
                        out('%4d | %s'%(j+1,s[j][:240]))
                        included.add(j)
    out('')
    out('DIAGNOSTIC_ENDED. No model or training file modified.')
    report_and_bundle(lines, episode, rec_path, neighbors)
    print('TARGET_RECEIPT player=%r spell=%r kind=%r step=%r origin=%r'%(owner,spell,event.get('kind'),step,event.get('cast_origin')))
    if 1<=step<=len(transitions):
        print('SELECTED_STEP_OWNER=%r request_type=%r'%(step_owner,transitions[step-1].get('request_type')))
    print('STEP_OWNER_MISMATCHES='+str(len(mismatches)))
    print('EVIDENCE_READY')
    return 0


def report_and_bundle(lines, episode, receipt_path, neighbors):
    REPORT.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    include = [
        'ai/python/v5m1_effect_receipts.py',
        'ai/python/train_v5_momentumone_reset.py',
        'build_v5_r3_effect_receipts.py',
        'r3_game_effect_methods.gd.inc',
        'build_v5m1_roomcast_provenance.py',
        'ai/game_school_cached.gd',
        'ai/ai_policy_school_v5_match.gd',
    ]
    with zipfile.ZipFile(BUNDLE, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=7) as z:
        z.write(REPORT, REPORT.name)
        z.writestr('v5m1_game399_nearby_transitions.json', json.dumps(neighbors,ensure_ascii=False,indent=2))
        if receipt_path is not None and receipt_path.exists():
            z.write(receipt_path,'game399_receipts.json')
        for rel in include:
            p=ROOT/rel
            if p.is_file() and p.stat().st_size<=2000000:
                z.write(p,'sources/'+rel)
        # only the log tail, not raw large JSONL episode
        logs=sorted(LOGS.glob('v5m1_pilot_from311_*.txt'),key=lambda p:p.stat().st_mtime,reverse=True)
        if logs:
            logtxt=logs[0].read_text(encoding='utf-8-sig',errors='replace')
            z.writestr('last_pilot_log_tail.txt', '\n'.join(logtxt.splitlines()[-100:]))
        z.writestr('NOT_INCLUDED.txt','Raw episode JSONL deliberately excluded (usually 30–50 MB). Report and receipts are read-only extracts. No weights/checkpoint included.\n')
    print('V5M1_GAME399_DIAGNOSTIC_SAVED '+str(REPORT))
    print('V5M1_GAME399_EVIDENCE_BUNDLE '+str(BUNDLE))


if __name__ == '__main__':
    raise SystemExit(main())
