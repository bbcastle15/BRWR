from pathlib import Path
from reportlab.pdfgen import canvas
import pypdfium2 as pdfium
p=Path('brwr/assets/avatars/possessed/production/symbols')
fs=sorted(f for f in p.glob('*.png') if '_white' not in f.name)
c=canvas.Canvas('build-user-data/anubis_glyph_review.pdf',pagesize=(1000,1200))
for i,f in enumerate(fs):
    x=(i%10)*100;y=1100-(i//10)*100
    c.drawImage(str(f),x,y,90,90,mask='auto');c.drawString(x+20,y,f.stem)
c.save();d=pdfium.PdfDocument('build-user-data/anubis_glyph_review.pdf');d[0].render().to_pil().save('build-user-data/anubis_glyph_review.png')
