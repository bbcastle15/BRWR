"""Codex Arcanum pp. 68–82: personal spells, using shared engine effects.

Idempotent content migration. Original art is never replaced. The small Codex
personal-card extracts are fallbacks until the user supplies full-resolution PNGs.
"""
import copy
import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
D = ROOT / "data"
spells = json.loads((D / "spells.json").read_text(encoding="utf-8"))
mages = json.loads((D / "mages.json").read_text(encoding="utf-8"))
manifest = json.loads((ROOT / "docs/mage-art-2026-10-23/manifest.json").read_text(encoding="utf-8"))
cards = {c["id"]: c for c in manifest["cards"]}

def e(t, **kw): return dict(type=t, **kw)
def side(t, element, target, distance, effects, **kw):
    return dict(type=t, element=element, target=target, range=distance, effects=effects, **kw)
def own(*effects): return e("self_effect", effects=list(effects))
def room(*effects, distance=0, **kw): return e("room_effect", range=distance, effects=list(effects), **kw)
def here(*effects): return e("self_room_effect", effects=list(effects))
def choose(*options):
    return e("choose_one", options=[dict(id=str(i), label=label, effects=effects) for i,(label,effects) in enumerate(options)])
def opt(*effects, prompt="Use this optional Effect?"): return e("optional_effect", prompt=prompt, effects=list(effects))
def model(*effects, **kw): return e("filtered_model_effect", effects=list(effects), **kw)
def scale(value, effect, **kw): return e("scaled_school_effect", value=value, effect=effect, **kw)
def on_trigger(*effects):
    return [dict(x, only_on_trigger=True) for x in effects]
def persistent(t, el, target, dist, effects=None, **kw):
    return side(t, el, target, dist, effects or [], persistent=True, **kw)
def mage(id, spell_id, title, L, R=None, instability=False):
    c=cards[id]; h,hand,strength,speed,quests=c["stats"]
    mages[id]=dict(id=id,name=c["name"],health=h,hand_limit=hand,strength=strength,
                   speed=speed,max_active_quests=quests,personal_spell_id=spell_id)
    card=dict(id=spell_id,name=title,school="personal",personal=True,copies=3,
              instability=instability,light=L,dark=copy.deepcopy(L) if R is None else R,
              source=f"Codex Arcanum p. {c['codex_page']}, {c['name']}")
    old=next((i for i,x in enumerate(spells) if x['id']==spell_id),None)
    if old is None: spells.append(card)
    else: spells[old]=card
    dest=ROOT / "assets/spells/personal_codex" / f"{spell_id}.png"
    dest.parent.mkdir(exist_ok=True)
    if not dest.exists(): shutil.copyfile(ROOT / "docs/mage-art-2026-10-23/sources" / c["source"],dest)

C="contingency";B="combat";T="trap"
damage=lambda n:e("damage",amount=n)
power=lambda n:e("gain_power",amount=n)
move=lambda:e("mage_move",distance=1)
attack=lambda **kw:e("mage_attack",**kw)
summon=lambda id:e("summon_evocation",evocation_id=id)
activate=lambda **kw:e("activate_target_evocation_under_control",**kw)
jinx=lambda **kw:e("assign_jinx",**kw)

mage("agorix","natural_invocation","Natural Invocation",
 side(C,"earth","self",0,[e("place_target_colored_room",colors=["green"]),e("summon_familiar",id="eracleto")]),
 side(C,"earth","special","*",[room(e("activate_target_room",allow_reactivate=True),e("place_instability",amount=2),scale("instability_shortfall",e("heal_caster"),total=2),distance="*",room_colors=["green"])]))
mage("albedo","divine_judgement","Divine Judgement",
 side(T,"sacred","mage",1,[choose(("Inflict Damage based on the target's Trophies",[scale("target_trophies",damage(0),base=2,max=4)]),("Steal Power based on the target's Solved Quests",[scale("target_solved_quests",e("steal_power"),max=2)]))],trigger={"type":"caster_defeated_by_mage"},trigger_target="source_mage"))
mage("alhazred","symbiosis","Symbiosis",
 persistent(C,"profane","self",0,on_trigger(here(summon("dagon"))),trigger={"type":"caster_resolves_summon"}),
 side(C,"profane","special","*",[model(activate(),owner="self",distinct_key="symbiosis_evocations"),model(activate(strength_bonus=1),owner="self",distinct_key="symbiosis_evocations")]))
mage("alice","dark_passenger","Dark Passenger",
 persistent(B,"profane","self",0,passives={"spell_damage_to_other_mage_bonus":1,"instability_after_spell_damage_to_mage":1}),
 side(B,"profane","evocation",2,[e("remove_evocation_then",max_health=3,effects=[here(e("summon_removed_evocation")),e("removed_owner_power",amount=1)])]),True)
mage("alisha","bharatanatyam","Bharatanatyam",
 side(C,"air","mage",2,[jinx(id="divine_dance")]+[e("move_target_up_to",distance=1)]*3),
 persistent(C,"air","self",0,on_trigger(power(2)),trigger={"type":"another_mage_placed_in_cell"}),True)
mage("architect","magic_tunnel","Magic Tunnel",
 side(C,"magic","self",0,[e("place_self_in_room",room_id="black_rose"),room(e("activate_target_room",allow_reactivate=True),e("black_rose_power_if_room_activated",amount=1),distance=1)]),
 side(C,"magic","room",1,[e("remove_instability",amount=2,up_to=True),e("fixed_room_effect",room_id="black_rose",effects=[e("place_instability",amount=2)])]))
mage("arianna","assembly_line","Assembly Line",
 side(C,"profane","room",0,[summon("cadaver"),e("if_effect_result",key="last_summoned_evocation",effects=[e("assign_upgrade",choice=True),e("activate_summoned_evocation")])]),
 side(C,"profane","evocation","*",[model(e("remove_evocation_then",owned=True,effects=[room(summon("colossus"),e("if_effect_result",key="last_summoned_evocation",effects=[e("assign_upgrade",choice=True)]),distance="*")]),use_primary=True,owner="self",archetype="undead",has_upgrade=True)],target_owner="self",target_archetype="undead",target_has_upgrade=True),True)
mage("baron_doria","wanderers_dream","Wanderer's Dream",
 side(C,"profane","mage","*",[e("school_condition",condition="target_nightmares",minimum=1,effects=[],otherwise=[e("assign_nightmare",evocation_id="umbra")]),model(activate(strength_bonus=2),archetype="nightmare",assigned_to_target=True)]),
 side(C,"profane","special","*",[e("remove_many_evocations",archetype="nightmare",amount=2,effects=[e("repeat_counted_effect",key="school_removed_count",effects=[model(e("assign_nightmare",evocation_id="umbra"),e("activate_last_nightmare"),target="mage")])])]),True)
mage("bella","elemental_spirits","Elemental Spirits",
 persistent(C,"all","self",0,passives={"damage_reduction":1}),
 persistent(B,"all","room",0,passives={"combat_spell_damage_bonus":1}),True)
mage("cacus","giant_stampede","Giant Stampede",
 side(B,"earth","self",0,[e("move_then_effect",effects=[here(damage(2))])]*2),
 side(B,"earth","room",0,[damage(3),e("place_instability",amount=2)]),True)
mage("boogeyman","technodomain","Technodomain",
 side(C,"profane","room",0,[e("summon_in_unoccupied_type_room",evocation_id="doll",range=1)]*3+[model(activate(),owner="self",evocation_id="doll")]),
 side(C,"profane","special","*",[model(e("for_school_mages",range=0,include_self=True,effects=[e("convert_damage",amount=2)]),owner="self")]))
mage("cosma","gifts_of_death","Gifts of Death",
 side(C,"profane","evocation","*",[model(activate(),e("if_effect_result",key="last_activated_evocation",effects=[power(1)]),use_primary=True,archetype="undead",distinct_key="gifts_undead"),model(activate(),e("if_effect_result",key="last_activated_evocation",effects=[power(1)]),archetype="undead",distinct_key="gifts_undead")],target_archetype="undead"),
 side(C,"profane","self",0,[e("draw_random_memories_up_to",amount=3,cost="power")]))
mage("fenrir","blood_rage","Blood Rage",
 persistent(C,"magic","self",0,on_trigger(attack()),trigger={"type":"mage_event","event_type":"damage_inflicted","target":"self","min_amount":1}),
 side(B,"magic","room",1,[scale("caster_damage",damage(0),divisor=2,max=4)]))
mage("gramigna","evil_eye","Evil Eye",
 side(C,"all","mage",2,[power(1),move(),jinx(choice=True)]),
 side(C,"all","self",0,[e("discard_quest_or_jinx",effects=[power(1),e("draw_quest",amount=1)])]))
mage("griphon","foretold_flight","Foretold Flight",
 side(C,"air","self",0,[e("prophecy"),e("move_per_board_event",suppressed_trigger_types=["trap"])]),
 side(B,"earth","model",0,[e("prophecy"),e("attack_selected_target",ignore_protection_if_events=3)]))
mage("helblindi","jotuns_vindar","Jotuns Vindar",
 persistent(C,"fire","model",2,on_trigger(damage(2)),trigger={"type":"marked_model_leaves_room"}),
 side(C,"fire","room",3,[damage(2),e("place_caster_in_target_room")]),True)
mage("hyperion","burning_the_sky","Burning the Sky",side(B,"all","special","*",[e("hyperion_personal")]))
mage("ignis","molten_core","Molten Core",
 side(B,"fire","room",2,[damage(2),e("place_instability",amount=1)],enhancement={"requires":["fire","fire"],"effects":[damage(2),e("place_instability",amount=1)]},resolution_order=["enhancement","base"]),
 side(B,"fire","room",1,[e("damage_per_target_room_instability",max_amount=4)],enhancement={"requires":["fire"],"effects":[e("place_instability",amount=2)]},resolution_order=["enhancement","base"],suppressed_trigger_types=["protection","trap"]))
mage("irene","notes_of_the_magister","Notes of the Magister",
 side(C,"magic","special","*",[choose(("Draw 2 Spells and gain 1 Power",[e("draw_grimoire",amount=2),power(1)]),("Discard 4 Spells to draw a Forgotten Spell",[e("conditional_payment",cost=e("discard_spell",amount=4,**{"from":"hand"},destination="memories"),effects=[e("draw_forgotten",amount=1)])]))]),
 side(T,"magic","self",0,[e("peek_forgotten_keep_bottom",amount=2)],trigger={"type":"mage_event","event_type":"forgotten_spell_drawn","source":"other"},trigger_target="self"))
mage("jack","extinguishing_light","Extinguishing Light",
 persistent(C,"magic","self",0,on_trigger(opt(model(e("assign_destiny"),target="mage"))),trigger={"type":"mage_placed_in_cell"}),
 side(B,"profane","mage",2,[e("assign_destiny"),damage(2),e("school_condition",condition="target_survived",effects=[e("gain_target_trophy")])]))
mage("jukas","time_twister","Time Twister",
 side(C,"all","self",0,[e("draw_random_memories_up_to",amount=3,cost="damage")]),
 side(C,"all","room",2,[e("discard_hand_for_effect",amount=2,effects=[scale("discarded_spells",damage(0),multiplier=2)])]),True)
mage("maelice","malia","Malia",
 side(C,"profane","mage",2,[e("steal_power",amount=1),jinx(id="spinning_wheel_sting"),move()]),
 persistent(C,"profane","self",0,on_trigger(e("trigger_target_effect",effects=[e("convert_damage",amount=1)])),trigger={"type":"black_rose_damages_another_mage"}),True)
mage("minotaurus","drums_of_war","Drums of War",
 side(B,"earth","special","*",[e("each_mage_move_attack",power_per_attack=1,max=3)]),
 side(B,"earth","self",0,[move(),here(scale("mage_strength",damage(0)))]),True)
mage("odin","asgardian_winds","Asgardian Winds",
 side(B,"air","model",1,[scale("owned_evocations",damage(0),archetype="equipment",base=1,max=4),e("school_condition",condition="target_survived",effects=[e("summon_equipment")])]),
 side(B,"air","model",2,[damage(1),e("move_target_up_to",distance=1),e("move_target_up_to",distance=1),e("target_discard_hand",amount=1)]))
mage("razvan","blood_pact","Blood Pact",
 side(C,"profane","room",0,[e("pain",amount=3),e("choose_evocation_to_summon",max_health=3)]),
 side(C,"profane","evocation",2,[e("remove_evocation_then",max_health=3,effects=[own(e("heal",amount=3))])]))
mage("rubedo","chaos_strike","Chaos Strike",
 side(B,"all","self",0,[opt(e("place_caster_in_vastum_room")),attack(optional=True,effects=[e("chaos")])]),
 side(B,"all","self",0,[move(),attack(optional=True,effects=[e("place_vastum",room_source="target_model")])]),True)
mage("saba","light_and_shadow","Light and Shadow",
 side(C,"profane","self",0,[choose(("Solve an Active Quest",[e("solve_active_quest")]),("Assign 2 random Jinxes",[model(jinx(),target="mage",range=1)]*2))]),
 side(C,"profane","mage","*",[jinx(),e("target_mage_room_effect",effects=[summon("pharaoh")])]))
mage("shroudtech","contagium","Contagium",
 side(C,"magic","room",2,[e("repeat_paid_effect",repeats=2,effects=[choose(("Convert 1 Instability",[e("convert_instability",amount=1)]),("Place 1 Instability",[e("place_instability",amount=1)]))])]),
 side(B,"magic","mage",2,[e("target_discard_hand",amount=3,up_to=True),scale("discard_shortfall",e("convert_damage"),total=3),scale("discard_shortfall",e("draw_grimoire"),total=3)]),True)
mage("slenderman","unio_perpetua","Unio Perpetua",
 side(C,"profane","room",2,[e("place_caster_in_target_room"),e("pay_power_or_effect",amount=1,effects=[here(e("convert_instability",amount=2))],otherwise=[opt(here(e("place_instability",amount=1)))])]),
 persistent(C,"sacred","self",0,on_trigger(opt(e("discard_triggering_persistent"),e("ignore_trigger_damage",amount=999),prompt="Discard Unio Perpetua to ignore this Damage?")),trigger={"type":"you_suffer_damage"}),True)
mage("talia","mastery","Mastery",side(B,"all","room",1,[
 e("geoform",room_colors=["red","purple"],effects=[damage(3)]),
 e("geoform",room_colors=["green","yellow"],effects=[e("place_instability",amount=3)]),
 e("geoform",room_colors=["blue","grey","gray"],effects=[e("draw_grimoire",amount=2),own(e("heal",amount=2)),opt(e("place_caster_in_target_room"))]),
 e("geoform",room_colors=["black"],effects=[e("convert_instability",amount=2),e("steal_power",amount=1)])]))
mage("ulrich","imperishable_fate","Imperishable Fate",
 persistent(C,"profane","self",0,[e("each_owned_evocation",effects=[e("damage_selected_evocation",amount=1,black_rose=True)],only_on_initial_cast=True)],passives={"evocation_strength_bonus":1}),
 side(C,"profane","special","*",[model(activate(),archetype="undead",distinct_key="imperishable_undead")]*2))

# Its three-body state and additional Cells are not supported by the single-
# model runtime yet. Keep the sourced material, but never offer a broken Mage.
mages['hyperion']['implemented'] = False
mages['hyperion']['excluded_forgotten_spell_ids'] = ['a_burning_world']

for name, data in [("spells",spells),("mages",mages)]:
    (D/f"{name}.json").write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
evocations={x['id']:x for x in json.loads((D/'evocations.json').read_text(encoding='utf-8'))}
evocations['doll']=dict(id='doll',name='Doll',archetype='undead',additional_archetypes=['construct'],
                       health=2,strength=2,speed=2,copies=3,
                       abilities=[dict(type='before_defeat_effect',optional=True,range=2,damage_equal_strength=True)],
                       source='Codex Arcanum p.72')
evocations['eracleto']=dict(id='eracleto',name='Eracleto',archetype='beast',familiar=True,
                          health=3,strength=2,speed=2,copies=1,
                          abilities=[dict(type='attack_bonus_against_undamaged',amount=1)],
                          source='Codex Arcanum p.68; Magister pp.8–10; FAQ Eracleto setup')
(D/'evocations.json').write_text(json.dumps(list(evocations.values()),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print("Registered 31 additional Mages and their Personal Spells.")

# Older, already implemented Mages use the same Codex fallback until a user's
# full-resolution Personal Spell is present. SpellArtResolver prefers that art.
for mage_data in mages.values():
    source_card = cards.get(mage_data['id'])
    if source_card is None:
        continue
    dest = ROOT / 'assets/spells/personal_codex' / (mage_data['personal_spell_id'] + '.png')
    if not dest.exists():
        shutil.copyfile(ROOT / 'docs/mage-art-2026-10-23/sources' / source_card['source'], dest)
