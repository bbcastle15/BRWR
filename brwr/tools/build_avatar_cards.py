"""Typeset Avatar cards from authoritative JSON over new HD artwork.

Original screenshots remain references. Text is real PDF typography, then
rendered at 1024x1536; no screenshot scaling or OCR text enters the output.
Run with the bundled Python (reportlab + pypdfium2).
"""
from pathlib import Path
import json
from xml.sax.saxutils import escape
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.colors import HexColor
import pypdfium2 as pdfium

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/avatars/possessed/hd'
PDF = ROOT / 'docs/handoff-2026-10-18/evidence/avatar_cards_hd.pdf'
for name, filename in [('Card','georgia.ttf'),('CardBold','georgiab.ttf'),('CardItalic','georgiai.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(Path('C:/Windows/Fonts') / filename)))
pdfmetrics.registerFontFamily('Card', normal='Card', bold='CardBold', italic='CardItalic', boldItalic='CardBold')
W,H = 1024,1536
C = canvas.Canvas(str(PDF), pagesize=(W,H))
manifest = []

def block(text, top, height, size=38, x=105, width=814, color='#201c17', bold=False):
    for pts in range(size,25,-1):
        style=ParagraphStyle('card',fontName='CardBold' if bold else 'Card',fontSize=pts,leading=pts*1.32,
                             textColor=HexColor(color),alignment=1,spaceAfter=12)
        p=Paragraph(text,style)
        _,h=p.wrap(width,height)
        if h<=height: break
    else: raise ValueError(f'Text does not fit: {text}')
    p.drawOn(C,x,top-h-(height-h)/2)

def base(title, subtitle):
    C.setPageSize((W,H))
    C.drawImage(str(OUT/'card_template.png'),0,0,W,H)
    block(escape(title),H-125,115,52,color='#f5dfac',bold=True)
    block(subtitle,H-215,42,27,color='#f0d8a5')

def finish(id):
    manifest.append(id)
    C.showPage()

def effect(e):
    t=e['type']; n=e.get('amount',1)
    mapping={
        'damage':f'Inflicts <b>{n} Damage</b>.',
        'convert_damage':f'Converts <b>{n} Damage</b>.',
        'damage_each_mage':f'Inflicts <b>{n} Damage</b> to each Mage.',
        'convert_each_mage':f'Converts <b>{n} Damage</b> on each Mage.',
        'damage_models_around_target':f'Inflicts <b>{n} Damage</b> to each Model within distance {e.get("range",0)} of the target.',
        'damage_models_around_self':f'Inflicts <b>{n} Damage</b> to each Model within distance {e.get("range",0)} of the Avatar.',
        'damage_per_ignored':'Inflicts <b>1 Damage</b> to the target for each Damage ignored due to this Effect.',
        'discard_hand':f'The target discards <b>{n} Spells</b> from their Hand.',
        'discard_each_hand':f'Each Mage discards <b>{n} Spells</b> from their Hand.',
        'target_power_per_missing_conversion':'The target loses <b>1 Power</b> for each Damage not converted due to this Effect.',
        'target_power_per_missing_discard':'The target loses <b>1 Power</b> for each Spell not discarded due to this Effect.',
        'power':f'Gains <b>{n} Power</b>.',
        'additional_command':'<b>+ Reveal and resolve an additional Command.</b>',
        'ignore_damage':f'Ignores <b>{n} Damage</b> on itself.',
        'instability_per_ignored':'Places <b>1 Instability</b> in its Room for each Damage ignored due to this Effect.',
        'ignore_spell':'Ignores the <b>Combat Spell Effect</b>.',
        'trophy':'Obtains <b>1 Trophy</b> of the target.',
        'release_energy':'If the target Room is the Black Rose Room, places <b>2 Instability</b> in that Room.',
        'release_force':'If the target Room is the Black Rose Room, places <b>2 Instability</b> there. Otherwise, converts <b>1 Instability</b> in the target Room.',
        'instability':f'Places <b>{n} Instability</b> in the target Room.',
        'remove_target_evocation':f'The target removes one of their Evocations with Health {e.get("max_health",3)} or less.',
        'remove_per_discard':f'For each Spell discarded due to this Effect, the target removes one of their Evocations with Health {e.get("max_health",3)} or less.',
    }
    if t in mapping: return mapping[t]
    if t=='move_toward':
        color=e['color']
        destination='the Black Rose Room' if color=='black' else (f'a <b>{color} Room</b>' if color else f'a Mage, using <b>Priority {e["priority"]}</b>')
        return f'Moves toward {destination}.'
    if t=='heal':
        result=f'Heals {"up to " if e.get("up_to") else ""}<b>{n} Damage</b>.'
        if e.get('power_per_missing'): result+=' Gains <b>1 Power</b> for each Damage not healed due to this Effect.'
        if e.get('power_if_none'): result+=' If it did not heal any Damage due to this Effect, gains <b>1 Power</b>.'
        return result
    if t=='summon': return f'Summons a <b>{e["evocation_id"].title()}</b> in the Black Rose Room.'
    if t=='activate_evocation': return f'A <b>{e["evocation_id"].title()}</b> of the Avatar activates.'
    if t=='activate_without_effect':
        rewards={'power':f'gains <b>{n} Power</b>', 'quest':'draws and solves <b>1 Quest</b> of the current Moon',
                 'cadavers':'summons a <b>Cadaver</b> in its Room. If it summoned a Cadaver, summons another <b>Cadaver</b> in its Room'}
        return 'Activates the target Room without generating any Effect. If it does, '+rewards[e['reward']]+'.'
    raise ValueError(t)

def section_text(s):
    text=[]
    if s.get('instability'): text.append('<b>Instability:</b> first place 1 Instability in the Avatar\'s Room.')
    if s.get('priority'): text.append(f'<b>Priority {s["priority"]}.</b>')
    text += [effect(e) for e in s.get('effects',[])]
    return '<br/>'.join(text)

def panel(label,text,top,height,meta=''):
    C.setStrokeColor(HexColor('#92784c')); C.setLineWidth(2)
    C.line(104,top,920,top)
    block(escape(label),top-12,40,30,bold=True)
    if meta: block(escape(meta),top-57,40,26)
    block(text,top-(104 if meta else 60),height-(115 if meta else 72),37)

commands=json.loads((ROOT/'data/avatar_commands.json').read_text())
events=json.loads((ROOT/'data/avatar_events.json').read_text())
for card in commands:
    base(card['name'],f'POSSESSED · COMMAND {card["number"]:02d} · MOON {card["moon"]}')
    sections=card['sections'][:]
    if card['reaction']: sections.append(dict(card['reaction'],kind='reaction'))
    height=880/len(sections)
    for i,s in enumerate(sections):
        label='PHYSICAL ACTION' if s['kind']=='physical' else ('PROTECTION · REACTION' if s['kind']=='reaction' else s['type'].upper()+' SPELL')
        meta=''
        if s['kind']=='spell': meta=f'{s.get("element", "").title()} · {s.get("target", "special").title()} · Range {"*" if s.get("range",-1)<0 else s["range"]}'
        if s['kind']=='reaction':
            meta={'damage':'When the Avatar is about to suffer Damage', 'suffered_damage':'Targets the Mage who inflicted that Damage', 'combat_spell':'Targets the Mage who cast that Combat Spell'}[s['trigger']]
        panel(label,section_text(s),1205-i*height,height,meta)
    block('Resolve from top to bottom.<br/>Physical movement uses the Avatar\'s Speed.',255,115,28)
    finish(card['id'])

event_text={
    'traces_of_texture':'If the Avatar is in a green, grey, or purple Room, the Avatar places <b>2 Instability</b> in its Room.',
    'remnants_of_magic':'If the Avatar is in a red, yellow, or blue Room, the Avatar places <b>2 Instability</b> in its Room.',
    'divinatory_secrets':'If a Mage activates a yellow or grey Room, they gain <b>1 Power</b>.<br/><br/>The Avatar inflicts <b>1 Damage</b> to each Mage who activates a yellow or grey Room.',
    'thorny_corruption':'Each time a Mage places at least <b>2 Instability</b> due to a single Effect, the Avatar converts <b>1</b> of those Instability Cubes.',
    'crown_of_thorns':'The Mage who owns the Crown gains <b>1 Power</b>.<br/><br/>The Avatar inflicts <b>2 Damage</b> to the Mage who owns the Crown.',
    'illness':'The Avatar converts <b>1 Damage</b> on each Mage with at least 1 Damage from the Avatar on their Mage Sheet.',
    'letters_of_destruction':'If a Mage activates a green or red Room, they gain <b>1 Power</b>.<br/><br/>The Avatar inflicts <b>1 Damage</b> to each Mage who activates a green or red Room.',
    'singing_victory_again':'Each Mage with less Power than the Avatar gains <b>1 Power</b>.<br/><br/>Each Mage with more Power than the Avatar loses <b>1 Power</b>.',
    'magic_of_the_rose':'If the Avatar is within distance <b>1</b> of the Black Rose Room, the Avatar places <b>2 Instability</b> in the Black Rose Room.',
    'revolt_of_the_servants':'Each Mage, in play order, chooses to lose <b>1 Power</b> or remove one of their own Evocations.',
    'cursed_trophy':'Each Mage with at least 1 Trophy of the Avatar loses <b>1 Power</b>.',
    'manipulating_the_past':'Each Mage discards <b>1 solved Quest</b>.',
    'sorrow':'Each Mage with at least 1 Damage from the Avatar loses <b>1 Power</b>.',
    'pledge':'The Avatar inflicts <b>2 Damage</b> to each Mage within distance <b>1</b> of the Avatar.',
    'conspiracy_book':'If a Mage activates a purple or blue Room, they gain <b>1 Power</b>.<br/><br/>The Avatar inflicts <b>1 Damage</b> to each Mage who activates a purple or blue Room.',
}
for card in events:
    base(card['name'],f'AVATAR EVENT · MOON {card["moon"]}'+(' · CROWN' if card['crown'] else ''))
    block(event_text[card['id'].removeprefix('avatar_')],1130,690,45)
    block(card['phase'].replace('_',' ').upper()+' PHASE' if card['phase']!='instant' else 'INSTANT',420,75,36,bold=True)
    block(f'Reveal: <b>{card["reveal_power"]} Power</b> · Discard: <b>{card["discard_power"]} Power</b><br/>'+('Resolve immediately.' if card['slot']==0 else f'Event Board · Slot {card["slot"]}'),255,120,31)
    finish(card['id'])

base('Avatar Commands','POSSESSED · GRIMOIRE / HAND')
block('THE BLACK ROSE<br/><br/><b>COMMAND DECK</b><br/><br/>Unrevealed faces and order are hidden.',1130,690,50)
block('Reveal a Command only when instructed.<br/>Place revealed Commands in Memories.',270,130,30)
finish('command_back')

# Landscape Avatar card, matching the original slot orientation.
C.setPageSize((1536,1024))
C.setFillColor(HexColor('#10292c')); C.rect(0,0,1536,1024,fill=1,stroke=0)
C.drawImage(str(OUT/'possessed_illustration.png'),0,0,730,1024)
C.setFillColor(HexColor('#f0dfbc')); C.roundRect(738,25,775,974,20,fill=1,stroke=0)
C.setStrokeColor(HexColor('#ae9465')); C.setLineWidth(7); C.roundRect(10,10,1516,1004,22,fill=0,stroke=1)
block('POSSESSED',960,85,65,x=785,width=685,bold=True)
block('<b>12 HEALTH · 2 STRENGTH · 2 SPEED</b>',858,80,34,x=785,width=685)
block('<b>DOMINION</b><br/>If Possessed must activate while in a Cell, it does not activate and places itself in the Black Rose Room.',750,220,35,x=785,width=685)
block('<b>PRIORITY 1</b><br/>Most Damage / Nearest Room / Most Power<br/><br/><b>PRIORITY 2</b><br/>Nearest Room / Most Power / Most Trophies<br/><br/><b>PRIORITY 3</b><br/>Most Mages / Most Models / Most Instability',505,365,31,x=785,width=685)
block('Ties and unresolved choices: owner of the Crown.',120,75,27,x=785,width=685)
finish('possessed')
C.save()
doc=pdfium.PdfDocument(str(PDF))
for i,id in enumerate(manifest):
    bitmap=doc[i].render(scale=1)
    bitmap.to_pil().save(OUT/(id+'.png'))
doc.close()
(OUT/'manifest.json').write_text(json.dumps({'cards':manifest,'source':'data/avatar_commands.json + data/avatar_events.json + supplied screenshots','resolution':'1024x1536; Avatar 1536x1024'},indent=2))
print(f'Typeset and rendered {len(manifest)} HD cards: {OUT}')
