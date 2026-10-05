"""Render the review DOCX content to PDFs without Office/LibreOffice."""

from html import escape
from io import BytesIO
from pathlib import Path

from docx import Document
from docx.oxml.ns import qn
from docx.table import Table as DocxTable
from docx.text.paragraph import Paragraph as DocxParagraph
from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.platypus import BaseDocTemplate, Frame, Image, PageBreak, PageTemplate, Paragraph, Spacer, Table, TableStyle


HERE = Path(__file__).resolve().parent
WIDTH, HEIGHT = A4


def para_image(paragraph, doc):
    blips = paragraph._p.xpath('.//a:blip')
    if not blips:
        return None
    rid = blips[0].get(qn('r:embed'))
    blob = doc.part.related_parts[rid].blob
    size = PILImage.open(BytesIO(blob)).size
    max_w, max_h = (295, 625) if size[1] > size[0] * 1.5 else (232, 235)
    scale = min(max_w / size[0], max_h / size[1])
    return Image(BytesIO(blob), width=size[0] * scale, height=size[1] * scale)


def render(src):
    doc = Document(src)
    styles = {
        'Title': ParagraphStyle('Title', fontName='Times-Bold', fontSize=22, leading=26, alignment=1, spaceAfter=16),
        'Heading 1': ParagraphStyle('H1', fontName='Times-Bold', fontSize=16, leading=19, spaceBefore=13, spaceAfter=7),
        'Heading 2': ParagraphStyle('H2', fontName='Times-Bold', fontSize=13, leading=16, spaceBefore=10, spaceAfter=5),
        'Normal': ParagraphStyle('Body', fontName='Times-Roman', fontSize=12, leading=15, spaceAfter=7),
        'Center': ParagraphStyle('Center', fontName='Times-Roman', fontSize=12, leading=15, alignment=1, spaceAfter=7),
        'Cell': ParagraphStyle('Cell', fontName='Times-Roman', fontSize=10.5, leading=12.5),
    }
    story = []
    for child in doc.element.body.iterchildren():
        if child.tag == qn('w:p'):
            p = DocxParagraph(child, doc)
            if any(br.get(qn('w:type')) == 'page' for br in p._p.xpath('.//w:br')):
                story.append(PageBreak())
                continue
            img = para_image(p, doc)
            if img:
                story.append(img)
                continue
            if not p.text.strip():
                story.append(Spacer(1, 9))
                continue
            sty = styles.get(p.style.name, styles['Normal'])
            if p.alignment == 1 and p.style.name == 'Normal':
                sty = styles['Center']
            value = escape(p.text).replace('\n', '<br/>')
            if p.runs and all(r.bold for r in p.runs if r.text):
                value = f'<b>{value}</b>'
            story.append(Paragraph(value, sty))
        elif child.tag == qn('w:tbl'):
            t = DocxTable(child, doc)
            rows = []
            has_image = False
            for row in t.rows:
                cells = []
                for c in row.cells:
                    image = next((para_image(p, doc) for p in c.paragraphs if para_image(p, doc)), None)
                    if image:
                        cells.append(image)
                        has_image = True
                    else:
                        cells.append(Paragraph(escape(c.text), styles['Cell']))
                rows.append(cells)
            col_widths = [238, 238] if has_image else [476 / len(rows[0])] * len(rows[0])
            tbl = Table(rows, colWidths=col_widths, hAlign='CENTER', repeatRows=0 if has_image else 1, splitByRow=0 if has_image else 1)
            ts = [
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ('LEFTPADDING', (0, 0), (-1, -1), 4),
                ('RIGHTPADDING', (0, 0), (-1, -1), 4),
                ('TOPPADDING', (0, 0), (-1, -1), 4),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
            ]
            if not has_image:
                ts += [('GRID', (0, 0), (-1, -1), .4, colors.grey), ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#e2e7e5'))]
            tbl.setStyle(TableStyle(ts))
            story.extend((Spacer(1, 5), tbl, Spacer(1, 7)))

    out = src.with_suffix('.pdf')
    def frame(canvas, document):
        canvas.saveState()
        canvas.setFont('Times-Roman', 9)
        canvas.drawCentredString(WIDTH / 2, HEIGHT - 29, 'M. Kumarasamy College of Engineering  |  Department of Computer Science and Business Systems')
        canvas.setStrokeColor(colors.grey)
        canvas.line(48, HEIGHT - 35, WIDTH - 48, HEIGHT - 35)
        canvas.drawCentredString(WIDTH / 2, 29, f'EG-Counter  •  {src.stem.split("_")[0]} 2026  •  Page {document.page}')
        canvas.restoreState()
    pdf = BaseDocTemplate(str(out), pagesize=A4, leftMargin=48, rightMargin=48, topMargin=48, bottomMargin=48)
    pdf.addPageTemplates(PageTemplate(id='report', frames=[Frame(48, 48, WIDTH - 96, HEIGHT - 96, leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)], onPage=frame))
    pdf.build(story)
    return out


if __name__ == '__main__':
    for month in ('August', 'September'):
        print(render(HERE / f'{month}_2026_Monthly_Progress_Review.docx'))
