"""Native reconstruction of Last Dynasty cards, using the existing Avatar
typesetting pipeline and original BRWR glyphs/fonts. Illustrations are separate
ImageGen assets. Never scale screenshot text or approximate a rules pictogram.
Run with bundled Python (reportlab, pypdfium2, pypdf).
"""
from pathlib import Path
from io import BytesIO
import json, re, hashlib, sys
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.colors import HexColor
import pypdfium2 as pdfium
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/avatars/possessed/production'
OUT=ROOT/'assets/avatars/anubis/approved'
ART=OUT.parent/'materials'
OUT.mkdir(parents=True,exist_ok=True)
SYMBOLS=BASE/'symbols'
for name in ['Title','Body','Bold','Italic']:
    pdfmetrics.registerFont(TTFont(name,str(BASE/'source_fonts'/f'{name}.ttf')))
pdfmetrics.registerFontFamily('Body',normal='Body',bold='Bold',italic='Italic',boldItalic='Bold')
pdfmetrics.registerFont(TTFont('Fallback', 'C:/Windows/Fonts/times.ttf'))
pdfmetrics.registerFont(TTFont('FallbackBold', 'C:/Windows/Fonts/timesbd.ttf'))
pdfmetrics.registerFont(TTFont('FallbackItalic', 'C:/Windows/Fonts/timesi.ttf'))
pdfmetrics.registerFontFamily('Fallback',normal='Fallback',bold='FallbackBold',italic='FallbackItalic',boldItalic='FallbackItalic')

# Reuse the existing font completeness check, without executing its builder.
source=(ROOT/'tools/build_avatar_production.py').read_text()
exec(source[source.index('def complete_text('):source.index('def icon(')],globals())

CODES={'D':'e902','I':'e904','P':'e901','T':'e90e','AV':'e9af','R0':'e939','R1':'e93a','R2':'e93b','R*':'e93d','M*':'e945','Q':'e9a3','C':'e905','black':'e914','green':'e919','yellow':'e918','grey':'e917','blue':'e916','purple':'e91b','red':'e91a','combat':'e950'}
def icon(code,size=48,white=False):
    path=SYMBOLS/(code+('_white' if white else '')+'.png')
    assert path.exists(),path
    return f'<img src="{path}" width="{size*1.28}" height="{size*1.28}" valign="middle"/>'
def symbolic(text,white=False,size=44):
    return re.sub(r'\{([^}]+)\}',lambda m:icon(CODES.get(m[1],m[1]),size,white and m[1] not in ['green','yellow','grey','blue','purple','red']),text)
def paragraph(c,text,x,top,w,h,size=48,white=False,font='Body'):
    text=symbolic(text,white,size*.9)
    # Check the actual run font, including italic names; a subset can contain
    # a letter in regular Garamond but omit its italic outline.
    parts=[]; italic=False; bold=False
    for part in re.split('(<[^>]*>)',text):
        if part=='<i>': italic=True
        elif part=='</i>': italic=False
        elif part=='<b>': bold=True
        elif part=='</b>': bold=False
        parts.append(part if part.startswith('<') else complete_text(part,'Italic' if italic else 'Bold' if bold else font))
    text=''.join(parts)
    for pts in range(size,25,-1):
        style=ParagraphStyle('card',fontName=font,fontSize=pts,leading=pts*1.22,alignment=1,textColor=HexColor('#f1e9d7' if white else '#171713'))
        p=Paragraph(text,style);_,height=p.wrap(w,h)
        if height<=h:break
    else:raise ValueError('Overflow '+text)
    p.drawOn(c,x,top-height-(h-height)/2)
def material(c,name,x,y,w,h):c.drawImage(str(BASE/name),x,y,w,h)
def ornament(c,y):
    c.setStrokeColor(HexColor('#aca596'));c.setLineWidth(7);c.line(50,y,974,y)
    c.setStrokeColor(HexColor('#e6dfce'));c.setLineWidth(2);c.line(50,y+3,974,y+3)
    for x,sign in [(52,1),(972,-1)]:
        p=c.beginPath();p.moveTo(x+sign*55,y+10);p.curveTo(x-sign*14,y+36,x-sign*20,y-29,x+sign*38,y-6);c.drawPath(p)
def moon(c,n,x,y,size=90):
    c.drawImage(str(ART/f'moon_{n}.png'),x-size/2,y-size/2,size,size,mask='auto',preserveAspectRatio=True,anchor='c')

def flag(c,code,x,top):
    c.setFillColor(HexColor('#111617'));c.setStrokeColor(HexColor('#817b69'));c.setLineWidth(2)
    p=c.beginPath();p.moveTo(x-70,top);p.lineTo(x+70,top);p.lineTo(x+70,top-105);p.lineTo(x,top-140);p.lineTo(x-70,top-105);p.close();c.drawPath(p,fill=1,stroke=1)
    c.drawImage(str(SYMBOLS/(code+'_white.png')),x-63,top-125,126,126,mask='auto')
def side_marker(c,code,top):
    if code == 'e953':
        c.drawImage(str(SYMBOLS/(code+'.png')),34,top-103,79,79,mask='auto')
    else:
        c.drawImage(str(SYMBOLS/(code+'_white.png')),34,top-103,79,79,mask='auto')

# Exact English source text; braces reference original BRWR glyphs, not fonts
# with lookalike Unicode characters. Numbers/ranges stay in their glyphs.
BODIES={
1:['Gains 1{T} of the target.<br/>Assigns a random Jinx to the target.<br/>{AV}'],
2:['Assigns a random Jinx to the target.<br/>Converts 1{D} for each Jinx assigned to the target.<br/>{AV}'],
3:['Gains 1{T} of the target.<br/>Assigns a random Jinx to the target.<br/>{AV}'],
4:['Assigns a random Jinx to the target.<br/>+{C}'],
5:['Converts 2{I}.'],6:['Inflicts 1{D}.<br/>Places 2{I}.'],
7:['Assigns a random Jinx to the target.<br/>Places 2{I} in a {R0} from the target for each Jinx assigned to it.', '{M*}: targets the Mage who inflicted the {D}.<br/>Inflicts 3{D}. The target removes one of their Evocations.'],
8:['Places 2{I}.<br/>Inflicts 1{D}.<br/>+{C}', '{R*}: targets a {R0} from the Mage who inflicted the {D}.<br/>Places 2{I}.<br/>Inflicts 3{D}.'],
9:['Draws and solves 1 Quest of the current Moon.<br/>Inflicts 2{D} to each Mage in the Lodge who has at least 1 Completed or Solved Quest.', '{M*}: targets the Mage who cast the {combat} Spell.<br/>The target discards 1 Solved Quest.<br/>Inflicts 2{D}.'],
10:['Summons a <i>Pharaoh</i> in a {R0} from the target.<br/>Summons a <i>Pharaoh</i> in the {black}.<br/>Reveals 1 Event of the current Moon.<br/>+{C}'],
11:['The target loses 2{P}. Assigns a random Jinx to the target.<br/>{AV}'],
12:['Assigns a random Jinx to the target.<br/>Converts 3{D} for each Jinx assigned to the target.<br/>{AV}'],
13:['Gains 1{T} of the target.<br/>Steals 1{P}.<br/>Assigns a random Jinx to the target.<br/>{AV}'],
14:['Assigns a random Jinx to the target.<br/>+{C}'],
15:['Converts 3{I}.<br/>Summons a <i>Pharaoh</i>.<br/>{AV}'],
16:['Inflicts 2{D}.<br/>Places 3{I}.'],
17:['Assigns a random Jinx to the target. Inflicts 3{D} for each Jinx assigned to the target.', '{M*}: targets the Mage who inflicted the {D}. Inflicts 3{D} for each Jinx assigned to the target.<br/>Summons a <i>Pharaoh</i> in a {R0} from the target.'],
18:['Places 3{I}.<br/>Inflicts 2{D}.<br/>+{C}', '{R*}: targets a {R0} from the Mage who inflicted the {D}.<br/>Places 3{I}.<br/>Inflicts 4{D}.'],
19:['Draws and solves 2 Quests of the current Moon.<br/>Inflicts 3{D} to each Mage in the Lodge who has at least 1 Completed or Solved Quest.', '{M*}: targets the Mage who cast the {combat} Spell.<br/>Steals 1 Solved Quest.<br/>Inflicts 2{D}.'],
20:['Summons a <i>Pharaoh</i> in a {R0} from the target.<br/>Summons a <i>Pharaoh</i> in a {R1} from the target, different from the previous Room.<br/>Summons a <i>Pharaoh</i> in the {black}.<br/>Reveals 1 Event of the current Moon.'],
21:['Gains 2{T} of the target.<br/>Assigns a random Jinx to the target.<br/>{AV}'],
22:['Assigns a random Jinx to the target.<br/>Steals 1{P} for each Jinx assigned to the target.<br/>{AV}'],
23:['Gains 1{T} of the target.<br/>Converts 3{D}. Steals 1{P} for each {D} that could not be converted with this Effect.<br/>Assigns a random Jinx to the target.<br/>{AV}'],
24:['Assigns a random Jinx to the target.<br/>Steals 1{P}.<br/>+{C}'],
25:['Converts 4{I}.<br/>Gains 1{P} for each {I} that could not be converted with this Effect.<br/>{AV}'],
26:['Inflicts 3{D}.<br/>Places 4{I}.'],
27:['Assigns a random Jinx to the target. The target is defeated; no Mage gains {P} due to this defeat.<br/>Gains 4{P}.', '{M*}: targets the Mage who inflicted the {D}. The target is defeated; no Mage gains {P} due to this defeat. Gains 3{P}.'],
28:['Places 4{I}. Gains 1{P} for each {I} that could not be placed with this Effect.<br/>Inflicts 3{D}.<br/>+{C}', 'Ignores all {D}.<br/>Places 3{I} in a {R0}.<br/>Gains 1{P} for each {I} that could not be placed with this Effect.'],
29:['Steals 1 Solved Quest from each Mage in the Lodge.<br/>Reveals 1 Event of the current Moon.', '{M*}: targets the Mage who cast the {combat} Spell.<br/>Steals 1 Solved Quest.<br/>Steals 1{P}.'],
30:['Summons a <i>Pharaoh</i>. It activates.<br/><br/>Summons a <i>Pharaoh</i>. It activates.<br/>Gains 1{P} for each Evocation they own.<br/>+{C}']}

manifest=[]
def render(id,draw,size=(1024,1536)):
    stream=BytesIO();c=canvas.Canvas(stream,pagesize=size);draw(c);c.showPage();c.save()
    doc=pdfium.PdfDocument(stream.getvalue())
    temporary=OUT/(id+'.png.tmp')
    doc[0].render(scale=1.5).to_pil().save(temporary,format='PNG');doc.close()
    temporary.replace(OUT/(id+'.png'))
    manifest.append({'id':id,'path':'assets/avatars/anubis/approved/'+id+'.png','sha256':hashlib.sha256((OUT/(id+'.png')).read_bytes()).hexdigest()})
def draw_card(c,card):
    sections=card['sections'][:]
    if card['reaction']:sections.append(dict(card['reaction'],kind='reaction'))
    template='single' if len(sections)==1 else 'reaction' if sections[-1]['kind']=='reaction' else 'physical_top' if sections[0]['kind']=='physical' else 'physical_bottom'
    c.drawImage(str(ART/(template+'.png')),0,0,1024,1536)
    paragraph(c,card['name'],60,1510,800,175,64,True,'Title');moon(c,card['moon'],945,1430,110)
    heights={'single':[1195],'reaction':[745,450],'physical_top':[330,865],'physical_bottom':[865,330]}[template]
    top=1310;body_index=0
    for section,height in zip(sections,heights):
        physical=section['kind']=='physical'
        side_marker(c,'e911' if physical else 'e953' if section['kind']=='reaction' else 'e905',top)
        if physical:
            e=section['effects'][0];color=e.get('color','')
            text=('{'+'e9b'+str(3+e['priority'])+'}. ' if e.get('priority') else '')
            text+='Moves towards '+('the target.' if not color else ('the ' if color=='black' else 'a ')+'{'+color+'}.')
            if len(section['effects'])>1:text+='<br/>Places 1{I} in a {R0}.'
            paragraph(c,text,135,top-40,775,height-70,51,True)
        else:
            text=BODIES[card['number']][body_index];body_index+=1
            offset=25
            if section['kind']=='spell':
                element={'profane':'e969','sacred':'e96a','magic':'e968','earth':'e966','fire':'e967'}[section['element']]
                target='e93f'
                if section['target']=='mage':target='e945' if section['range']<0 else 'e9%02x'%(0x41+section['range'])
                elif section['target']=='area':target='e93d' if section['range']<0 else 'e9%02x'%(0x39+section['range'])
                for x,code in zip([290,530,770],['e950' if section['type']=='combat' else 'e951',element,target]):flag(c,code,x,top)
                offset=155
                if section.get('priority'):text='{e9b'+str(3+section['priority'])+'}.<br/>'+text
            paragraph(c,text,132,top-offset,800,height-offset-25,49 if section['kind']=='spell' else 44)
        top-=height
    c.setFillColor(HexColor('#ece2cf'));c.setFont('Fallback',28);c.drawString(45,36,card['source'])

cards=[c for c in json.loads((ROOT/'data/avatar_commands.json').read_text()) if c['id'].startswith('anubis_')]
assert len(cards)==30
for card in cards:
    if '--extras-only' not in sys.argv: render(card['id'],lambda c,card=card:draw_card(c,card))

def draw_back(c,n,reaction):
    c.drawImage(str(ART/'portrait.png'),0,0,1024,1536)
    moon(c,n,512,480,235)
    c.setFillColor(HexColor('#091212'));c.rect(20,100,984,280,fill=1,stroke=0)
    ornament(c,380);ornament(c,100)
    paragraph(c,'Anubis',50,360,924,230,95,True,'Title')
    if reaction:
        c.setFillColor(HexColor('#0c1518'));c.setStrokeColor(HexColor('#bcb3a3'));c.setLineWidth(9)
        c.circle(770,820,185,fill=1,stroke=1);c.setLineWidth(3);c.circle(770,820,171,fill=0,stroke=1)
        # Position the original glyph by its ink bounds, not the padded atlas
        # square. The white shield includes its solid interior for the trigger.
        emblem(c,'e953_white',770,820,250)
        emblem(c,'e950' if reaction=='combat' else 'e902',770,835,96)

def emblem(c,code,x,y,size):
    path=SYMBOLS/(code+'.png')
    with Image.open(path) as im:
        left,top,right,bottom=im.getchannel('A').getbbox()
        w,h=im.size
    scale=size/max(right-left,bottom-top)
    c.drawImage(str(path),x-(left+right)*scale/2,y-(h-(top+bottom)/2)*scale,w*scale,h*scale,mask='auto')

for n in [1,2,3]:
    for reaction in ['', 'combat','damage']:
        id=f'anubis_command_back_{n}'+(f'_protection_{reaction}' if reaction else '')
        render(id,lambda c,n=n,reaction=reaction:draw_back(c,n,reaction))

def draw_sheet(c):
    c.setFillColor(HexColor('#091212'));c.rect(0,0,1400,1000,fill=1,stroke=0)
    c.drawImage(str(ART/'portrait.png'),0,0,700,1000)
    material(c,'parchment_material.png',720,30,650,940)
    for code,value,y in [('e91f','11',880),('e922','2',750),('e91e','2',620)]:
        c.drawImage(str(SYMBOLS/(code+'_white.png')),35,y,90,90,mask='auto')
        paragraph(c,value,130,y+90,110,90,65,True)
    c.setFillColor(HexColor('#091212'));c.rect(20,20,670,260,fill=1,stroke=0)
    paragraph(c,'Scourge, Pledge, Judgment,<br/>Divine Sandstorm, Dominion',45,270,620,130,40,True,'Italic')
    paragraph(c,'Anubis',45,130,620,100,76,True,'Title')
    paragraph(c,'{AV}: summons a <i>Pharaoh</i> in a {R0} from himself. An Evocation controlled by <i>Anubis</i> in a {R1} from the target activates.',755,900,580,430,45)
    paragraph(c,'{e9b4}{e940}: +{P}{e9b7}+{Q}{e9b7}+{T}{e9b7}+{D}.<br/>{e9b5}{e940}: +{D}{e9b7}+{T}{e9b7}+{Q}{e9b7}+{P}.<br/>{e9b6}{e938}: +{I}{e9b7}+{e940}{e9b7}+{e932}.',755,350,580,270,35)
    c.setFillColor(HexColor('#eee5d6'));c.setFont('Fallback',22);c.drawString(30,6,'BRW-LAS S-017')

render('anubis',draw_sheet,(1400,1000))
if '--extras-only' in sys.argv:
    manifest=[item for item in json.loads((OUT.parent/'manifest.json').read_text())['cards'] if item['id'] not in {m['id'] for m in manifest}]+manifest
for item in manifest: item['sha256']=hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()
(OUT.parent/'manifest.json').write_text(json.dumps({'method':'Existing native Avatar typography pipeline, original rulebook glyphs and fonts; ImageGen illustration separately credited.','source':'materials/avatars/anubis; materials/last.pdf pp.8-9','symbols':CODES,'cards':manifest},indent=2)+'\n')
print('Anubis: rendered',len(manifest),'assets')
