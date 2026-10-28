"""Build the Papi policy PDFs from their UTF-8 source texts."""
from html import escape
from pathlib import Path
import re
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer

root = Path(__file__).resolve().parents[2]
folder = Path(__file__).parent
fonts = root / 'Papi/Resources/Fonts'
for name, filename in [('PapiBody','PapiCounter-Regular.ttf'), ('PapiBodyBold','PapiCounter-SemiBold.ttf'), ('PapiTitle','PapiEditorial-Regular.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(fonts / filename)))

ink = colors.HexColor('#3f2921')
body = colors.HexColor('#4c3931')
muted = colors.HexColor('#856e61')
rule = colors.HexColor('#ded1c2')
paper = colors.HexColor('#fffaf3')
styles = {
    'brand': ParagraphStyle('brand', fontName='PapiBodyBold', fontSize=10.2, leading=13, textColor=ink, spaceAfter=18),
    'title': ParagraphStyle('title', fontName='PapiTitle', fontSize=27, leading=31, textColor=ink, spaceAfter=7),
    'date': ParagraphStyle('date', fontName='PapiBody', fontSize=9.5, leading=13, textColor=muted, spaceAfter=20),
    'heading': ParagraphStyle('heading', fontName='PapiBodyBold', fontSize=12, leading=16, textColor=ink, spaceBefore=13, spaceAfter=5, keepWithNext=True),
    'body': ParagraphStyle('body', fontName='PapiBody', fontSize=10.7, leading=15.7, alignment=TA_LEFT, textColor=body, spaceAfter=9, allowWidows=0, allowOrphans=0),
}

def decorate(canvas, doc):
    w,h=doc.pagesize
    canvas.saveState()
    canvas.setFillColor(paper); canvas.rect(0,0,w,h,stroke=0,fill=1)
    canvas.setStrokeColor(rule); canvas.setLineWidth(.5)
    canvas.line(30,h-29,w-30,h-29); canvas.line(30,29,w-30,29)
    canvas.setFillColor(muted); canvas.setFont('PapiBody',8.3)
    canvas.drawString(30,17,'PAPI  /  '+('USER AGREEMENT' if doc.policy=='terms' else 'PRIVACY POLICY'))
    canvas.drawRightString(w-30,17,str(doc.page))
    canvas.restoreState()

def build(policy):
    raw=(folder / (policy+'.txt')).read_text(encoding='utf-8').strip().split('\n\n')
    header=raw.pop(0).splitlines()
    title='User Agreement' if policy=='terms' else 'Privacy Policy'
    doc=SimpleDocTemplate(str(folder/(policy+'.pdf')),pagesize=(390,720),leftMargin=30,rightMargin=30,topMargin=42,bottomMargin=46,title='Papi '+title,author='Papi')
    doc.policy=policy
    story=[Paragraph('PAPI  /  YOUR COFFEE BOOK',styles['brand']),Paragraph(title,styles['title']),Paragraph(escape(header[1]),styles['date'])]
    for block in raw:
        lines=block.splitlines()
        if re.match(r'^\d+\. ',lines[0]):
            story.append(Paragraph(escape(lines.pop(0)),styles['heading']))
        if lines:
            content=escape(' '.join(lines)).replace('Papi_service2026@outlook.com','<link href="mailto:Papi_service2026@outlook.com" color="#704631">Papi_service2026@outlook.com</link>')
            story.append(Paragraph(content,styles['body']))
    doc.build(story,onFirstPage=decorate,onLaterPages=decorate)

for policy in ('terms','privacy'):
    build(policy)
