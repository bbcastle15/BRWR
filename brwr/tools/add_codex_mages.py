import json,pathlib
D=pathlib.Path('data');sp=json.loads((D/'spells.json').read_text(encoding='utf-8'));mg=json.loads((D/'mages.json').read_text(encoding='utf-8'))
def e(t,**kw):return dict(type=t,**kw)
def side(t,el,target,r,effects,**kw):return dict(type=t,element=el,target=target,range=r,effects=effects,**kw)
def mage(id,name,h,hand,card,title,school,L,R,inst=True,quests=2,speed=2):
 assert id not in mg and not any(s['id']==card for s in sp)
 mg[id]=dict(id=id,name=name,health=h,hand_limit=hand,strength=2,speed=speed,max_active_quests=quests,personal_spell_id=card)
 sp.append(dict(id=card,name=title,school=school,personal=True,copies=3,instability=inst,light=L,dark=R,source=f'Codex Arcanum, Mages: {name}'))
C='contingency';B='combat'
mage('cassandra','Cassandra',11,7,'pythia_of_delphi','Pythia of Delphi','oracle',side(C,'magic','self',0,[e('heal',amount=4),e('prophecy'),e('prophecy')]),side(C,'magic','room',0,[e('summon_evocation',evocation_id='aruspice'),e('activate_summoned_evocation'),e('summon_evocation',evocation_id='aruspice'),e('activate_summoned_evocation')]))
mage('venticello','Venticello',10,8,'the_eight_spells','The Eight Spells','personal',side(C,'light','self',0,[e('heal',amount=4),e('gain_power',amount=1),e('draw_quest',amount=1),e('draw_grimoire',amount=1)]),side(C,'light','model','*',[e('convert_damage',amount=1),e('relative_room_effect',range=0,effects=[e('convert_instability',amount=1),e('place_instability',amount=1)]),e('damage',amount=1)]))
mage('pestilentia','Pestilentia',10,8,'calamity','Calamity','pestilence',side(B,'air','room',2,[e('summon_evocation',evocation_id='pestis'),e('summon_evocation',evocation_id='pestis'),e('select_evocation_and_activate',evocation_id='pestis',range='*')]),side(B,'air','model',1,[e('assign_infectio',amount=2),e('damage',amount=2)]))
mage('sefu','Sefu',10,8,'mask_of_the_world','Mask of the World','shamanic',side(C,'earth','self',0,[e('gain_power',amount=1,only_on_trigger=True),e('draw_quest',amount=1,only_on_trigger=True)],trigger={'type':'caster_solves_quest'},trigger_target='self'),side(C,'earth','room',2,[e('place_instability',amount=2),e('gain_power',amount=1)]))
mage('hastur','Hastur',11,7,'demonic_crown','Demonic Crown','personal',side(C,'profane','self',0,[],passives={'damage_reduction':1}),side(C,'profane','none',0,[e('lose_power',amount=1),e('take_crown')]))
mage('prospero','Prospero',11,7,'alchemical_fireball','Alchemical Fireball','personal',side(B,'fire','room',2,[e('damage',amount=3)],suppressed_trigger_types=['protection']),side(B,'fire','room',1,[e('damage',amount=2),e('place_instability_per_damaged_model',amount_per_model=1)]),inst=False)
mage('dai_jin','Dai Jin',10,8,'fulu','Fulu','personal',side(C,'light','self',0,[e('gain_power',amount=1,only_on_initial_cast=True),e('draw_grimoire',amount=1,only_on_trigger=True)],trigger={'type':'caster_reveals_spell_type','spell_type':'combat'},trigger_target='self'),side(C,'light','self',0,[e('gain_power',amount=1,only_on_initial_cast=True),e('draw_quest',amount=1,only_on_trigger=True)],trigger={'type':'caster_reveals_spell_type','spell_type':'contingency'},trigger_target='self'))
(D/'spells.json').write_text(json.dumps(sp,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'mages.json').write_text(json.dumps(mg,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
