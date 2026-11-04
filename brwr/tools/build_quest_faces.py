"""Typeset Quest faces from the existing rules data with original BRWR glyphs.

Only presentation is generated. No changes to Quest rules or source PNGs.
Template: ImageGen restoration; symbols/fonts: existing official PDF extraction.
Run with the bundled Python runtime (reportlab + pypdfium2).
"""
from pathlib import Path
from io import BytesIO
import json, re, hashlib
from xml.sax.saxutils import escape
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph
import pypdfium2 as pdfium
from pypdf import PdfReader, PdfWriter
from pypdf.generic import DictionaryObject, NameObject, DecodedStreamObject

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/quests/symbols'
SOURCE = ROOT / 'assets/avatars/possessed/production'
TEMPLATE = ROOT / 'assets/quests/production/template.png'
GLYPHS = SOURCE / 'symbols'
OUT.mkdir(exist_ok=True)
original_glyphs = {}

def ensure_glyph(code, white=False):
    path = GLYPHS / (f'{code:04x}' + ('_white' if white else '') + '.png')
    if path.exists(): return path
    if not original_glyphs:
        reader = PdfReader(ROOT.parent/'materials/BRWR_CORE_rulebook_ENG_v1.2.pdf')
        for page_index in [15,14,25,40,22,37]:
            for ref in reader.pages[page_index]['/Resources']['/Font'].values():
                font = ref.get_object()
                if 'BRWR' not in str(font.get('/BaseFont','')) or font.get('/Subtype') != '/Type0': continue
                for source, dest in re.findall(r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>', font['/ToUnicode'].get_data().decode('latin1')):
                    original_glyphs.setdefault(int(dest,16),(ref,source))
    ref,cid = original_glyphs[code]
    writer = PdfWriter(); page = writer.add_blank_page(width=256,height=256)
    page[NameObject('/Resources')] = DictionaryObject({NameObject('/Font'):DictionaryObject({NameObject('/Original'):ref.clone(writer)})})
    color = HexColor('#eee5d0' if white else '#191919')
    stream = DecodedStreamObject()
    stream.set_data(f'{color.red:.4f} {color.green:.4f} {color.blue:.4f} rg BT /Original 160 Tf 20 64 Td <{cid}> Tj ET'.encode())
    page[NameObject('/Contents')] = writer._add_object(stream)
    buffer = BytesIO(); writer.write(buffer)
    doc = pdfium.PdfDocument(buffer.getvalue())
    doc[0].render(scale=2,fill_color=(255,255,255,0)).to_pil().save(path)
    doc.close()
    return path

for alias in ['Body', 'Bold', 'Italic', 'Title']:
    pdfmetrics.registerFont(TTFont(alias, str(SOURCE / 'source_fonts' / (alias+'.ttf'))))
pdfmetrics.registerFontFamily('Body', normal='Body', bold='Bold', italic='Italic', boldItalic='Bold')

ELEMENT = dict(air=0xe964, earth=0xe966, fire=0xe967, water=0xe96b, sacred=0xe96a, profane=0xe969, magic=0xe968, all=0xe965)
TYPE = dict(combat=0xe950, contingency=0xe951, protection=0xe953, trap=0xe952)
ROOM = dict(black=0xe914, grey=0xe917, red=0xe91a, blue=0xe916, purple=0xe91b, yellow=0xe918, green=0xe919)
SYMBOL = dict(Damage=0xe902, Instability=0xe904, Power=0xe901, Cube=0xe913, Health=0xe91f, Self=0xe93e, Crown=0xe903, Spell=0xe905, Quest=0xe9a4, Physical=0xe911, BlackRose=0xe9a0)
rooms = {room['id']:room for room in json.loads((ROOT/'data/rooms.json').read_text(encoding='utf-8'))}

def sym(code): return '{%04x}' % code
def word(name): return sym(SYMBOL[name])
def room_name(id): return rooms.get(id, {}).get('name', id.replace('_', ' ').title())
def elements(values, join=' or '): return join.join(sym(ELEMENT[e]) for e in values)
def targets(kind='self', distance='*'):
    if kind == 'self': return word('Self')
    base = {'room':0xe939, 'mage':0xe941, 'evocation':0xe947, 'model':0xe933}[kind]
    return sym(base + (4 if distance == '*' else int(distance)))

def task_text(card):
    t = card['task']; trigger = t['trigger']; condition = t.get('condition', '')
    if condition == 'revealed_spell_elements':
        icons = elements(t['elements']+['all'], ' / ')
        return f"After you resolve an Effect of one of your Spells and you have {t['required']} {icons} symbols on the Active Side of your Revealed Spells."
    if trigger == 'room_effect_resolved':
        where = room_name(t['room_id']) if 'room_id' in t else ' or '.join(sym(ROOM[v]) for v in t.get('room_colors', [t.get('room_color')]))
        text = f'After you resolve the {where} Effect'
    elif trigger in ['spell_resolved', 'effect_resolved']:
        if condition == 'places_instability': text = f"After you resolve an Effect that places at least {t['minimum']} {word('Instability')}"
        elif condition == 'places_or_converts_instability_in_room_color':
            text = f"After you resolve an Effect that converts or places at least {t['minimum']} {word('Instability')} in a {sym(ROOM[t['room_color']])}"
        elif t.get('keyword') == 'summon': text = 'After you resolve a Summon Effect'
        else:
            kind = ' or '.join(sym(TYPE[s]) for s in t.get('spell_types', [t['spell_type']] if 'spell_type' in t else []))
            if 'elements' in t: kind = elements(t['elements'])
            text = 'After you resolve ' + ('a ' + kind + ' Spell' if kind else 'a Spell Effect')
            if 'in_room_id' in t: text += ' while you are in the ' + room_name(t['in_room_id'])
    elif trigger == 'damage_or_heal_evocation': text = f"After you inflict or heal at least {t['minimum']} {word('Damage')} to an Evocation"
    elif trigger == 'damage_inflicted': text = f"After you inflict at least {t['minimum']} {word('Damage')}"
    elif trigger == 'mage_defeated': text = f"After a Mage with at least 1 of your {word('Damage')} on their Mage Sheet is defeated"
    else: raise ValueError('Unhandled task '+str(t))
    if card['cube_slots']:
        text += f", place 1 {word('Cube')} on this card."
        if t.get('reveal_immediately'): text = 'Reveal this card.<br/>' + text
        else: text += '<br/>The first time you do it, reveal this card.'
    else: text += '.'
    return text

def effect_text(e):
    kind = e['type']; n = e.get('amount', 1)
    prefix = targets(e.get('target', 'self'), e.get('range', '*')) + ': '
    if e.get('include_self'): prefix = targets('model') + ' or ' + word('Self') + ': '
    if kind in ['place_instability', 'convert_instability', 'convert_damage', 'damage', 'heal']:
        verb, resource = {'place_instability':('Place','Instability'), 'convert_instability':('Convert','Instability'), 'convert_damage':('Convert','Damage'), 'damage':('Inflict','Damage'), 'heal':('Heal','Damage')}[kind]
        return prefix + f'{verb} {n} {word(resource)}.'
    if kind == 'return_revealed_spell_to_hand': return word('Self') + ': Return 1 of your Revealed Spells with ' + elements(e['required_elements'] + ['all']) + ' on its Active Side to your Hand.'
    if kind == 'search_grimoire_to_hand': return prefix + f'Search your Grimoire for {n} Spell and add it to your Hand.'
    if kind == 'remove_evocation_with_max_health': return prefix + f"Remove the target if its {word('Health')} value is {e['max_health']} or less."
    if kind == 'draw_grimoire_or_heal': return prefix + f"Draw {e['draw']} Spells from your Grimoire, or heal {e['heal']} {word('Damage')}."
    if kind == 'activate_target_evocation_under_control': return prefix + 'Activate an <i>Undead</i> under your control.'
    if kind == 'activate_owned_evocation': return prefix + 'Activate one of your Evocations.'
    if kind in ['draw_library', 'draw_grimoire', 'draw_forgotten']:
        source = {'draw_library':'the Library', 'draw_grimoire':'your Grimoire', 'draw_forgotten':'the Forgotten Spell Deck'}[kind]
        return prefix + f"Draw {n} Spell{'s' if n > 1 else ''} from {source}."
    if kind == 'take_crown': return prefix + 'Take the ' + word('Crown') + '.'
    if kind == 'summon_evocation': return prefix + 'Summon a <i>' + e['evocation_id'].replace('_',' ').title() + '</i>.'
    if kind == 'activate_summoned_evocation': return 'It activates.'
    if kind == 'swap_with_target_mage_optional': return prefix + "You may place your Mage in the target Mage's Room. If you do, place the target in a Room of your choice."
    if kind == 'draw_event_optional_gain_power': return prefix + f"You may draw {n} Event. If you do, gain {e['power']} {word('Power')}."
    if kind == 'gain_power_if_no_damage': return prefix + f"If you have no {word('Damage')} on your Mage Sheet, gain {n} {word('Power')}."
    if kind == 'heal_all_damage': return prefix + f"Heal all {word('Damage')} on your Mage Sheet."
    if kind == 'draw_event_then_damage': return prefix + f"You may draw {n} Event. If you do, inflict {e['damage']} {word('Damage')} to a {targets('mage',e['range'])}."
    if kind == 'damage_all_models_lodge': return f"Inflict {n} {word('Damage')} to each Model in the Lodge."
    if kind == 'draw_quest': return prefix + f'Draw {n} Quest.'
    if kind == 'place_target_mage_then_damage': return prefix + f"Place the target in the {room_name(e['room_id'])}. Inflict {e['damage']} {word('Damage')}."
    if kind == 'shuffle_memories_into_grimoire_then_draw': return prefix + f'Shuffle your Memories into your Grimoire, then draw {n} Spells from your Grimoire.'
    if kind == 'summon_non_forgotten_evocation_choice': return prefix + 'Summon a non-Forgotten Evocation of your choice.'
    if kind == 'damage_or_place_instability': return prefix + f"Choose one: inflict {e['damage']} {word('Damage')}; or place {e['instability']} {word('Instability')}."
    if kind == 'complete_owned_quest_choice': return prefix + 'Complete one of your Quests.'
    if kind == 'black_rose_lose_power_or_target_mage_lose_power': return f"Choose an Effect: the {word('BlackRose')} loses {e['black_rose']} {word('Power')}; or a {targets('mage')} loses {e['mage']} {word('Power')}."
    if kind == 'refresh_physical_action_token': return prefix + f"One of your exhausted {word('Physical')} tokens becomes available."
    if kind == 'give_forgotten_to_target': return prefix + 'Give a Forgotten Spell in your Hand to the target; they add it to their Hand. If you do, solve this Quest.'
    if kind == 'draw_three_forgotten_keep_one': return prefix + f"Draw {e['draw']} Forgotten Spells; keep {e['keep']}, then discard the others."
    if kind == 'activate_evocation_or_summon_nigredo': return targets('evocation') + f": The target activates under your control. If there are no Evocations in the Lodge, summon a <i>Nigredo</i> in a {targets('room',e['range'])}. It activates."
    if kind == 'steal_power_from_up_to_mages': return f"Choose up to {e['max_targets']} {targets('mage')} and gain {e['amount_each']} {word('Power')} from each of them."
    raise ValueError('Unhandled effect '+str(e))

def paragraph(c, text, rect, maximum=58, minimum=37, color='#171714', font='Body'):
    x, top, width, height = rect
    # The supplied PDF fonts are subsets; preserve their original outlines,
    # but use a complete serif face for any missing letter (not a blank glyph).
    active_font = font
    complete = []
    for part in re.split(r'(<[^>]*>|\{e9[0-9a-f]{2}\})', text):
        if part.startswith('<') or part.startswith('{'):
            complete.append(part)
            if part in ['<i>','<b>']: active_font = 'Italic' if part == '<i>' else 'Bold'
            elif part in ['</i>','</b>']: active_font = font
            continue
        face = pdfmetrics.getFont(active_font).face
        for char in part:
            gid = face.charToGlyph.get(ord(char),0)
            if char.isspace() or (gid and face.glyphPos[gid+1] > face.glyphPos[gid]): complete.append(char)
            else:
                fallback = 'Times-Italic' if active_font == 'Italic' else ('Times-Bold' if active_font == 'Bold' else 'Times-Roman')
                complete.append(f'<font name="{fallback}">{char}</font>')
    text = ''.join(complete)
    for pts in range(maximum, minimum-1, -1):
        def glyph(match):
            path = ensure_glyph(int(match[1],16), color == '#fff4d5')
            return f'<img src="{path}" width="{pts*1.38}" height="{pts*1.38}" valign="middle"/>'
        rich = re.sub(r'\{(e9[0-9a-f]{2})\}', glyph, text)
        p = Paragraph(rich, ParagraphStyle('quest', fontName=font, fontSize=pts, leading=pts*1.35, alignment=1, textColor=HexColor(color)))
        _, actual = p.wrap(width, height)
        if actual <= height:
            p.drawOn(c, x, top-actual-(height-actual)*.5)
            return pts
    raise ValueError('Quest text does not fit: '+text)

quests = json.loads((ROOT/'data/quests.json').read_text(encoding='utf-8'))
manifest = dict(source='data/quests.json', template='assets/quests/production/template.png', glyph_source='BRWR_CORE_rulebook_ENG_v1.2.pdf', cards={})
stream = BytesIO(); c = canvas.Canvas(stream, pagesize=(1024,1536))
for id, card in quests.items():
    c.drawImage(str(TEMPLATE), 0,0,1024,1536)
    title_size = paragraph(c, escape(card['name']), (100,1400,824,135), maximum=74, minimum=44, color='#fff4d5', font='Title')
    task = task_text(card)
    task_size = paragraph(c, task, (145,1218,734,410 if card['cube_slots'] else 430), maximum=62, minimum=38)
    if card['cube_slots']:
        count=card['cube_slots']; edge=38; gap=22; total=count*edge+(count-1)*gap
        c.setStrokeColor(HexColor('#46301c')); c.setLineWidth(4)
        for index in range(count): c.roundRect((1024-total)/2+index*(edge+gap),755,edge,edge,3,stroke=1,fill=0)
    effects = [effect_text(e) for e in card['effects']]
    # The activation is the continuation of the Summon Effect, not a new target.
    text = '<br/>'.join(effects).replace('.<br/>It activates.', '. It activates.')
    effect_size = paragraph(c, text, (140,620,744,382), maximum=59, minimum=36)
    paragraph(c, str(card['power_reward']) + sym(0xe901), (704,212,194,100), maximum=78, minimum=60, color='#fff4d5')
    c.showPage()
    manifest['cards'][id] = dict(name=card['name'], task=task, effects=effects, font_sizes=[title_size,task_size,effect_size])
c.save()
pdf = pdfium.PdfDocument(stream.getvalue())
for page_index, id in enumerate(quests):
    pdf[page_index].render(scale=1).to_pil().save(OUT/(id+'.png'))
    manifest['cards'][id]['sha256'] = hashlib.sha256((OUT/(id+'.png')).read_bytes()).hexdigest()
pdf.close()
manifest['notes'] = ['Existing Crimson Star art and runtime both use range 3; stale raw_effect range 1 is not used.', 'Summoner elements use authoritative Profane/all, not the stale raw_task word Summon.', 'Original PNGs are preserved; only the card-art resolver prefers these faces.']
(ROOT/'assets/quests/production/manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(f'Typeset {len(quests)} Quest faces; no overflow; minimum body size {min(min(c["font_sizes"][1:]) for c in manifest["cards"].values())}.')
