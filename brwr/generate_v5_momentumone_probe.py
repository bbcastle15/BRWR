#!/usr/bin/env python3
"""Create Python-truth Godot probability test vectors, without training."""
from pathlib import Path
import json
import sys
import torch
ROOT = Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'ai/python'))
import v5_momentum_one as g


def option(i, family):
    return {'id': i, 'detail': {'kind': 'finish', 'descriptor': {}} if family=='finish'
            else {'kind': 'action', 'descriptor': {'kind':family},'action': {'type':family}}}


def build():
    cases=[]
    patterns=[(['momentum']*21 + ['cast']*2,'action_activation_step'),
              (['explore']*38 + ['momentum']*11 + ['fight']*2 + ['cast']*3 + ['finish'],'action_activation_step'),
              (['explore']*3 + ['cast']*3 + ['momentum']*7,'action_activation_step'),
              (['momentum']*17 + ['cast']*2,'effect_choice'),
              (['cast']*1 + ['finish']*1,'action_activation_step'),
              (['explore']*150 + ['momentum']*21 + ['cast']*2 + ['fight']*5,'action_activation_step'),
              (['momentum']*1 + ['cast']*2,'action_activation_step')]
    for index,(families,req) in enumerate(patterns):
        cs=[option(i,f) for i,f in enumerate(families)]
        scores=[round(((i*13 + index*7)%19 -9)*0.17,6) if index != 0 else 0.
                for i in range(len(cs))]
        actual = g.log_probabilities(torch.tensor(scores,dtype=torch.float32),cs,req).exp().tolist()
        cases.append({'request_type':req,'candidates':cs,'scores':scores,'expected':actual})
    out=ROOT/'ai/model/v5_momentumone_probe.json'
    out.parent.mkdir(parents=True,exist_ok=True)
    tmp=out.with_suffix('.json.tmp')
    tmp.write_text(json.dumps({'version':g.VERSION,'cases':cases},separators=(',',':')),encoding='utf-8')
    tmp.replace(out)
    print(f'MOMENTUM_ONE_PROBE_OK cases={len(cases)}',flush=True)

if __name__=='__main__':build()
