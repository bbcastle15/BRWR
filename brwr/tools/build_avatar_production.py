"""Rebuild native Avatar graphics; extract original symbols/fonts from rulebook.

No screenshots or generative text enter the generated faces or board. Source
illustrations/card backs are restored separately with ImageGen. Run bundled Python.
"""
from pathlib import Path
from io import BytesIO
import json, re, math, random, struct
from pypdf import PdfReader, PdfWriter
from pypdf.generic import DictionaryObject, NameObject, DecodedStreamObject
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.colors import HexColor
import pypdfium2 as pdfium

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/avatars/possessed/production'
OUT.mkdir(parents=True, exist_ok=True)
SYMBOLS = OUT / 'symbols'
SYMBOLS.mkdir(exist_ok=True)
FONTS = OUT / 'source_fonts'
FONTS.mkdir(exist_ok=True)
(FONTS/'.gdignore').write_text('')
SOURCE = ROOT.parent / 'materials/BRWR_CORE_rulebook_ENG_v1.2.pdf'
reader = PdfReader(SOURCE)
glyphs = {}
for page_index in [24, 25, 37, 34, 10, 14, 16, 22, 26, 27, 39, 40, 11, 12, 23, 30]:
    for key, ref in reader.pages[page_index]['/Resources']['/Font'].items():
        font = ref.get_object()
        if 'BRWR' in str(font.get('/BaseFont', '')) and font.get('/Subtype') == '/Type0':
            cmap = font['/ToUnicode'].get_data().decode('latin1')
            for source, dest in re.findall(r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>', cmap):
                code = int(dest, 16)
                if 0xe900 <= code <= 0xe9ff: glyphs.setdefault(code, (ref, source))

colors = {0xe914:'#252326',0xe917:'#aaa6a1',0xe91a:'#b53436',0xe916:'#78afd3',0xe91b:'#8a6caa',0xe918:'#e4b623',0xe919:'#7b9e49',0xe915:'#976bab'}
writer = PdfWriter()
codes = [(code,white) for white in [False,True] for code in sorted(glyphs)]
for code,white in codes:
    ref, cid = glyphs[code]
    page = writer.add_blank_page(width=256, height=256)
    page[NameObject('/Resources')] = DictionaryObject({NameObject('/Font'):DictionaryObject({NameObject('/Original'):ref.clone(writer)})})
    color = HexColor('#eee5d0' if white else colors.get(code, '#191919'))
    stream = DecodedStreamObject()
    stream.set_data(f'{color.red:.4f} {color.green:.4f} {color.blue:.4f} rg BT /Original 160 Tf 20 64 Td <{cid}> Tj ET'.encode())
    page[NameObject('/Contents')] = writer._add_object(stream)
buffer = BytesIO()
writer.write(buffer)
doc = pdfium.PdfDocument(buffer.getvalue())
for i, (code,white) in enumerate(codes):
    doc[i].render(scale=2, fill_color=(255,255,255,0)).to_pil().save(SYMBOLS / (f'{code:04x}'+('_white' if white else '')+'.png'))
doc.close()

# These TrueType fonts are embedded in the supplied rulebook and contain the
# actual title/body typography. Source remains unchanged.
def complete_font(family):
    """Reunite original glyphs from PDF subsets sharing the original glyph IDs."""
    subsets=[]; seen=set()
    for page in reader.pages:
        for ref in page['/Resources'].get('/Font',{}).values():
            f=ref.get_object()
            if str(f.get('/BaseFont','')).split('+')[-1] != family: continue
            descriptor=f.get('/FontDescriptor',{})
            if '/FontFile2' not in descriptor: continue
            stream=descriptor['/FontFile2']; raw=stream.get_data()
            if raw in seen: continue
            seen.add(raw)
            face=TTFont('subset',BytesIO(raw)).face
            subsets.append(face)
    base=subsets[0]; n=base.numGlyphs
    assert all(f.numGlyphs==n for f in subsets),family
    segments=[]; offsets=[0]
    for index in range(n):
        candidates=[f._ttf_data[f.table['glyf']['offset']+f.glyphPos[index]:f.table['glyf']['offset']+f.glyphPos[index+1]] for f in subsets]
        data=max(candidates,key=len); data+=b'\0'*(-len(data)%4)
        segments.append(data); offsets.append(offsets[-1]+len(data))
    tables={tag:base._ttf_data[info['offset']:info['offset']+info['length']] for tag,info in base.table.items()}
    head=bytearray(tables['head']); head[8:12]=b'\0'*4; head[50:52]=struct.pack('>h',1)
    tables.update(glyf=b''.join(segments),loca=struct.pack('>'+str(n+1)+'I',*offsets),head=bytes(head))
    def checksum(data):
        data+=b'\0'*(-len(data)%4)
        return sum(struct.unpack('>'+str(len(data)//4)+'I',data)) & 0xffffffff
    count=len(tables); power=2**int(math.log2(count)); offset=12+16*count
    header=struct.pack('>IHHHH',0x10000,count,power*16,int(math.log2(power)),count*16-power*16)
    entries=[]; payload=[]; head_offset=0
    for tag,data in sorted(tables.items()):
        if tag=='head': head_offset=offset
        entries.append(struct.pack('>4sIII',tag.encode(),checksum(data),offset,len(data)))
        padded=data+b'\0'*(-len(data)%4); payload.append(padded); offset+=len(padded)
    result=bytearray(header+b''.join(entries)+b''.join(payload))
    result[head_offset+8:head_offset+12]=struct.pack('>I',(0xb1b0afba-checksum(bytes(result))) & 0xffffffff)
    return bytes(result)

for alias, family in [('Title','BRWR_Titles'),('Body','AppleGaramond'),('Bold','AppleGaramond-Bold'),('Italic','AppleGaramond-Italic')]:
    font_path = FONTS / f'{alias}.ttf'
    font_path.write_bytes(complete_font(family))
    pdfmetrics.registerFont(TTFont(alias, str(font_path)))
pdfmetrics.registerFontFamily('Body',normal='Body',bold='Bold',italic='Italic',boldItalic='Bold')
for alias,filename in [('Fallback','times.ttf'),('FallbackBold','timesbd.ttf')]:
    pdfmetrics.registerFont(TTFont(alias,str(Path('C:/Windows/Fonts')/filename)))

def complete_text(text,font):
    # A PDF subset may omit outlines of letters never printed in the source.
    # Keep original typography wherever available; never emit blank letters.
    face=pdfmetrics.getFont(font).face
    def fix(part):
        result=''
        for char in part:
            gid=face.charToGlyph.get(ord(char),0)
            present=char.isspace() or (gid and face.glyphPos[gid+1]>face.glyphPos[gid])
            result+=char if present else '<font name="'+('FallbackBold' if font=='Bold' else 'Fallback')+'">'+char+'</font>'
        return result
    return ''.join(part if part.startswith('<') else fix(part) for part in re.split('(<[^>]*>)',text))

def icon(code, size=44):
    assert code in glyphs, f'Missing original glyph {code:04x}'
    # PDF glyph pages are 256 units, original glyph occupies ~160 units.
    return f'<img src="{SYMBOLS / f"{code:04x}.png"}" width="{size*1.48}" height="{size*1.48}" valign="middle"/>'

P=icon(0xe901); D=icon(0xe902); I=icon(0xe904); A=icon(0xe9a0); CROWN=icon(0xe903)
ROOM={'black':0xe914,'grey':0xe917,'red':0xe91a,'blue':0xe916,'purple':0xe91b,'yellow':0xe918,'green':0xe919}
R0=icon(0xe939); R1=icon(0xe93a)
manifest=[]

def paper(c,x,y,w,h):
    path=OUT/'parchment_material.png'
    if path.exists(): c.drawImage(str(path),x,y,w,h)

def dark_material(c,x,y,w,h):
    path=OUT/'board_material.png'
    if path.exists():
        c.drawImage(str(path),x,y,w,h)
        c.saveState(); c.setFillAlpha(.5); c.setFillColor(HexColor('#10221f')); c.rect(x,y,w,h,fill=1,stroke=0); c.restoreState()

def render(id, draw):
    stream=BytesIO(); c=canvas.Canvas(stream,pagesize=(1024,1536))
    draw(c); c.showPage(); c.save()
    pdf=pdfium.PdfDocument(stream.getvalue())
    pdf[0].render(scale=1.5).to_pil().save(OUT/(id+'.png'))
    pdf.close(); manifest.append(id)

def paragraph(c,text,x,top,w,h,size=48,color='#201d18',font='Body'):
    text=complete_text(text,font)
    for pts in range(size,26,-1):
        style=ParagraphStyle('face',fontName=font,fontSize=pts,leading=pts*1.35,alignment=1,textColor=HexColor(color))
        p=Paragraph(text,style); _,height=p.wrap(w,h)
        if height <= h: break
    else: raise ValueError('Text overflow: '+text)
    p.drawOn(c,x,top-height-(h-height)/2)

def ornament(c,y):
    c.setStrokeColor(HexColor('#c9bea4')); c.setLineWidth(3)
    c.line(45,y,979,y); c.line(65,y+8,959,y+8)
    for x,sign in [(58,1),(966,-1)]:
        for j in range(3):
            p=c.beginPath(); p.moveTo(x,y-16+j*8)
            p.curveTo(x+sign*70,y+25+j*3,x+sign*75,y-34,x+sign*20,y-10)
            c.drawPath(p)

def frame(c,title,event=False,moon=1):
    c.setFillColor(HexColor('#172321' if not event else '#c7bda6')); c.roundRect(5,5,1014,1526,32,fill=1,stroke=0)
    if not event: dark_material(c,28,28,968,1480)
    # Native grain/filigree: crisp vector detail, no captured border or moire.
    rnd=random.Random(72)
    c.setStrokeColor(HexColor('#263733' if not event else '#b4aa94')); c.setLineWidth(.5)
    for _ in range(260):
        x=rnd.randrange(12,1012); y=rnd.randrange(12,1524)
        c.line(x,y,x+rnd.randrange(-12,12),y+rnd.randrange(8,45))
    c.setStrokeColor(HexColor('#a99a79')); c.setLineWidth(2); c.roundRect(24,24,976,1488,23,fill=0,stroke=1)
    if event:
        c.setFillColor(HexColor('#ede2ca')); c.roundRect(48,65,928,1408,55,fill=1,stroke=0)
        paper(c,65,85,894,1368)
        paragraph(c,title,65,1445,894,130,64,font='Title')
        paragraph(c,'AVATAR',75,1325,874,65,42,font='Bold')
        ornament(c,1240)
    else:
        paragraph(c,title,65,1490,820,130,60,color='#e4dcc5',font='Title')
        # Native moon silhouette: crescent, half, full in the source position.
        c.setFillColor(HexColor('#cbb98e')); c.circle(939,1428,32,fill=1,stroke=0)
        if moon < 3:
            c.setFillColor(HexColor('#172321'))
            if moon==1: c.circle(953,1438,29,fill=1,stroke=0)
            else: c.rect(939,1394,35,70,fill=1,stroke=0)
        ornament(c,1360)

def room(color): return icon(ROOM[color])
def symbolic(text):
    for word, glyph in [('Damage',D),('Instability',I),('Power',P),('Trophy',icon(0xe90e))]:
        text=re.sub(r'\b'+word+r'\b',lambda match: glyph,text)
    return text

# Import just the existing effect transcription without running its old builder.
source=(ROOT/'tools/build_avatar_cards.py').read_text()
scope={}
exec(source[source.index('def effect('):source.index('def section_text(')],scope)
effect=scope['effect']

def effect_text(e):
    if e['type']=='move_toward':
        return (icon(0xe9b3+e['priority'])+', ' if e.get('priority') else '')+'moves toward '+(room(e['color']) if e.get('color') else 'a Mage')+'.'
    text=effect(e)
    text=re.sub(r'<b>(.*?)</b>',r'\1',text)
    text=text.replace('the Black Rose Room',room('black')).replace('in its Room','in a '+R0).replace('in the target Room','in the target '+icon(0xe938))
    return symbolic(text)

commands=json.loads((ROOT/'data/avatar_commands.json').read_text())
for card in commands:
    def draw(c,card=card):
        frame(c,card['name'],moon=card['moon'])
        sections=card['sections'][:]
        if card['reaction']: sections.append(dict(card['reaction'],kind='reaction'))
        texts=[]
        for s in sections:
            text='<br/>'.join(effect_text(e) for e in s.get('effects',[]))
            if s.get('priority'): text=icon(0xe9b3+int(s['priority']))+'<br/>'+text
            texts.append(text)
        weights=[max(3, len(re.sub('<[^>]*>','',t))/40) for t in texts]
        weights=[1.7 if s['kind']=='physical' else w for s,w in zip(sections,weights)]
        top=1330; total=sum(weights)
        for s,text,weight in zip(sections,texts,weights):
            h=1210*weight/total
            dark=s['kind']!='spell'
            c.setFillColor(HexColor('#182725' if dark else '#e5ddc8')); c.rect(48,top-h+6,928,h-12,fill=1,stroke=0)
            if dark: dark_material(c,48,top-h+6,928,h-12)
            else: paper(c,48,top-h+6,928,h-12)
            if dark:
                symbol=0xe911 if s['kind']=='physical' else 0xe953
                paragraph(c,icon(symbol,48).replace('.png','_white.png'),48,top-8,80,85,38)
                for code in glyphs:
                    if code not in colors or code==0xe914: text=text.replace(f'{code:04x}.png',f'{code:04x}_white.png')
                if s['kind']=='reaction':
                    trigger=s.get('trigger')
                    if trigger=='suffered_damage': text=icon(0xe945).replace('.png','_white.png')+': targets the Mage which inflicted that '+D.replace('.png','_white.png')+'.<br/>'+text
                    elif trigger=='combat_spell': text='Targets the Mage which cast that '+icon(0xe950).replace('.png','_white.png')+'.<br/>'+text
            else:
                # Source flags: spell type, element and target/range.
                element={'air':0xe964,'fire':0xe967,'water':0xe96b,'earth':0xe966,'magic':0xe968,'sacred':0xe96a,'profane':0xe969}.get(s.get('element'),0xe965)
                typ=0xe950 if s.get('type')=='combat' else 0xe951
                target={'model':0xe933,'mage':0xe941,'area':0xe939,'room':0xe939}.get(s.get('target'),0xe93e)
                distance=int(s.get('range',0))
                if s.get('target') in ['model','mage','area','room']: target+=distance if distance>=0 else 4
                flags=icon(typ,48)+icon(element,48)+icon(target,48)
                paragraph(c,flags,180,top-5,664,95,38)
                paragraph(c,icon(0xe905,42)+(icon(0xe904,38) if s.get('instability') else ''),48,top-12,100,145,34)
            paragraph(c,text,135,top-(55 if dark else 100),772,h-(80 if dark else 125),46,color='#e9e2ce' if dark else '#171713')
            top-=h; ornament(c,top)
        c.setFont('Fallback',24); c.setFillColor(HexColor('#e1d4b2')); c.drawString(55,21,f'BRW-REB M-{card["number"]:03d}')
    render(card['id'],draw)

event_body={
'traces_of_texture':f'If the Avatar is in a {room("green")}, {room("grey")}, or {room("purple")}, the {A} places 2{I} in a {R0} from the Avatar.',
'remnants_of_magic':f'If the Avatar is in a {room("red")}, {room("yellow")}, or {room("blue")}, the {A} places 2{I} in a {R0} from the Avatar.',
'divinatory_secrets':f'If a Mage activates a {room("yellow")} or {room("grey")}, they gain 1{P}.<br/>The {A} inflicts 1{D} to each Mage that activates a {room("yellow")} or {room("grey")}.',
'thorny_corruption':f'Each time a Mage places at least 2{I} due to a single Effect, the {A} converts 1 of those {I}.',
'crown_of_thorns':f'The Mage that owns the {CROWN} gains 1{P}.<br/>The {A} inflicts 2{D} to the Mage that owns the {CROWN}.',
'illness':f'The {A} converts 1{D} on each Mage with at least 1{D} from the {A} on their Mage Sheet.',
'letters_of_destruction':f'If a Mage activates a {room("green")} or {room("red")}, they gain 1{P}.<br/>The {A} inflicts 1{D} to each Mage that activates a {room("green")} or {room("red")}.',
'singing_victory_again':f'Each Mage with less {P} than the {A} gains 1{P}.<br/>Each Mage with more {P} than the {A} loses 1{P}.',
'magic_of_the_rose':f'If the Avatar is in a {R1} from {room("black")}, the {A} places 2{I} in the {room("black")}.',
'revolt_of_the_servants':f'Each Mage, in play order, chooses to lose 1{P} or remove one of their own Evocations.',
'cursed_trophy':f'Each Mage with at least 1{icon(0xe90e)} of the {A} loses 1{P}.',
'manipulating_the_past':'Each Mage discards 1 solved Quest.',
'sorrow':f'Each Mage with at least 1{D} from the {A} loses 1{P}.',
'pledge':f'The {A} inflicts 2{D} to each {icon(0xe942)} from the Avatar.',
'conspiracy_book':f'If a Mage activates a {room("purple")} or {room("blue")}, they gain 1{P}.<br/>The {A} inflicts 1{D} to each Mage that activates a {room("purple")} or {room("blue")}.',
}
codes_event={'crown_of_thorns':31,'remnants_of_magic':32,'thorny_corruption':33,'traces_of_texture':34,'divinatory_secrets':35,'revolt_of_the_servants':36,'singing_victory_again':37,'magic_of_the_rose':38,'letters_of_destruction':39,'illness':40,'conspiracy_book':41,'cursed_trophy':42,'pledge':43,'sorrow':44,'manipulating_the_past':45}
for card in json.loads((ROOT/'data/avatar_events.json').read_text()):
    def draw(c,card=card):
        frame(c,card['name'],event=True)
        if card['crown']: paragraph(c,CROWN,420,1286,184,100,50)
        key=card['id'].removeprefix('avatar_')
        paragraph(c,event_body[key],100,1170,824,640,52)
        ornament(c,490)
        phase='Instant' if card['phase']=='instant' else card['phase'].replace('_',' ').title()+' Phase'
        paragraph(c,phase,170,465,684,100,52)
        for i in range(3):
            c.setFillColor(HexColor('#eadfc9' if card['slot']==i+1 else '#b7ae9b'))
            c.setStrokeColor(HexColor('#463e30')); c.setLineWidth(4)
            c.roundRect(305+i*145,170,120,155,8,fill=1,stroke=1)
            c.setFillColor(HexColor('#c6bba4')); c.circle(365+i*145,248,43,fill=1,stroke=0)
            c.drawImage(str(SYMBOLS/'e9b0.png'),312+i*145,190,106,106,mask='auto')
        for x,right in [(110,False),(810,True)]:
            c.setStrokeColor(HexColor('#27251f')); c.setLineWidth(5); c.roundRect(x,220,105,150,6,fill=0,stroke=1)
            c.drawImage(str(SYMBOLS/'e9b0.png'),x+1,225,103,103,mask='auto')
            p=c.beginPath(); p.moveTo(x+25,345); p.curveTo(x+30,395,x+65,410,x+110,412); c.drawPath(p)
            c.line(x+110,412,x+90,429); c.line(x+110,412,x+88,395)
        paragraph(c,str(card['reveal_power'])+P,70,205,195,100,50)
        paragraph(c,str(card['discard_power'])+P,760,205,195,100,50)
        c.setFont('Fallback',26); c.setFillColor(HexColor('#3e3528')); c.drawString(70,34,f'BRW-REB M-{codes_event[key]:03d}')
    render(card['id'],draw)

# Native vector board. Coordinates match the authoritative board slots, with
# a straight, clean outer edge and no photographic material or screenshot crop.
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1450" height="700" viewBox="0 0 1450 700"><defs><linearGradient id="wood"><stop stop-color="#13221f"/><stop offset=".5" stop-color="#29342d"/><stop offset="1" stop-color="#101d1b"/></linearGradient><linearGradient id="recess"><stop stop-color="#080f0e"/><stop offset="1" stop-color="#263029"/></linearGradient></defs>']
outline='21,350 223,0 1450,0 1450,700 223,700'
svg.append(f'<polygon points="{outline}" fill="none" stroke="#b6a17b" stroke-width="5"/>')
svg.append('<path d="M40 350 L232 16 L1434 16 L1434 684 L232 684 Z" fill="none" stroke="#675f49" stroke-width="2"/>')
rnd=random.Random(28)
for _ in range(220):
    x=rnd.randrange(270,1415); y=rnd.randrange(55,670)
    svg.append(f'<path d="M{x} {y} q{rnd.randrange(8,25)} -4 {rnd.randrange(30,90)} 0" fill="none" stroke="#62725b" stroke-opacity=".12" stroke-width=".6"/>')
for x,y,w,h in [(267,52,372,276),(267,365,372,273),(698,44,412,602)]:
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="url(#recess)" stroke="#aa9770" stroke-width="2"/>')
    svg.append(f'<rect x="{x+8}" y="{y+8}" width="{w-16}" height="{h-16}" rx="8" fill="none" stroke="#4e5948"/>')
# Cube recesses are drawn from Power Board artwork by AvatarBoard.
svg.append('</svg>')
(OUT/'board.svg').write_text(''.join(svg))
(OUT/'manifest.json').write_text(json.dumps({'cards':manifest,'source_rulebook':str(SOURCE.name),'glyphs':{f'{k:04x}':v for k,v in colors.items()},'all_faces_native_typeset':True,'room_symbols':'Original embedded BRWR font, rulebook p25','command_convert_damage':'e902 (Damage), never e904 (Instability)'},indent=2))
print(f'Production: {len(manifest)} faces, {len(glyphs)} original symbols, native board.')
