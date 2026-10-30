"""
Builds the formal academic final project report: docs/FINAL_PROJECT_REPORT.docx
VIT Chennai Campus AI Digital Twin — Cloud Architecture and Design (CAD)
"""

import os
import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import parse_xml, OxmlElement
from docx.oxml.ns import nsdecls, qn

OUTPUT_PATH = "docs/FINAL_PROJECT_REPORT.docx"
os.makedirs("docs", exist_ok=True)

doc = docx.Document()

# -------------------------------------------------------------
# Page Layout Setup (A4, 1-inch margins)
# -------------------------------------------------------------
section = doc.sections[0]
section.page_width = Inches(8.27)
section.page_height = Inches(11.69)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)
section.different_first_page_header_footer = True

# Colors
COLOR_PRIMARY = RGBColor(0x1B, 0x36, 0x5D)    # Deep Navy (#1B365D)
COLOR_SECONDARY = RGBColor(0x2B, 0x4C, 0x7E)  # Slate Blue (#2B4C7E)
COLOR_TEXT = RGBColor(0x2D, 0x37, 0x48)       # Charcoal Body Text (#2D3748)
COLOR_MUTED = RGBColor(0x64, 0x74, 0x8B)      # Muted Gray (#64748B)
COLOR_DARK = RGBColor(0x0F, 0x17, 0x2A)       # Dark Slate (#0F172A)
COLOR_ACCENT = RGBColor(0xEA, 0x58, 0x0C)     # Amber/Orange (#EA580C)

# Configure Normal style
style_normal = doc.styles['Normal']
style_normal.font.name = 'Calibri'
style_normal.font.size = Pt(11)
style_normal.font.color.rgb = COLOR_TEXT
style_normal.paragraph_format.line_spacing = 1.15
style_normal.paragraph_format.space_after = Pt(6)

# -------------------------------------------------------------
# XML Formatting Helpers
# -------------------------------------------------------------
def set_cell_background(cell, fill_hex):
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{fill_hex}"/>')
    cell._tc.get_or_add_tcPr().append(shd)

def set_cell_margins(cell, top=120, bottom=120, left=150, right=150):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = parse_xml(
        f'<w:tcMar {nsdecls("w")}>'
        f'<w:top w:w="{top}" w:type="dxa"/>'
        f'<w:bottom w:w="{bottom}" w:type="dxa"/>'
        f'<w:left w:w="{left}" w:type="dxa"/>'
        f'<w:right w:w="{right}" w:type="dxa"/>'
        f'</w:tcMar>'
    )
    tcPr.append(tcMar)

def set_table_borders(table, color="CBD5E1", sz="4", val="single"):
    tblPr = table._tbl.tblPr
    tblBorders = parse_xml(
        f'<w:tblBorders {nsdecls("w")}>'
        f'<w:top w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
        f'<w:bottom w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
        f'<w:left w:val="none"/>'
        f'<w:right w:val="none"/>'
        f'<w:insideH w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
        f'<w:insideV w:val="none"/>'
        f'</w:tblBorders>'
    )
    tblPr.append(tblBorders)

def add_header_footer():
    # Header (pages after title page)
    header = section.header
    p_head = header.paragraphs[0]
    p_head.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    r_head = p_head.add_run("VIT Chennai Campus AI Digital Twin | Final Project Report")
    r_head.font.name = "Calibri"
    r_head.font.size = Pt(8.5)
    r_head.font.color.rgb = COLOR_MUTED

    # Footer
    footer = section.footer
    p_foot = footer.paragraphs[0]
    p_foot.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    r_foot1 = p_foot.add_run("Cloud Architecture and Design (CAD)  |  Page ")
    r_foot1.font.name = "Calibri"
    r_foot1.font.size = Pt(8.5)
    r_foot1.font.color.rgb = COLOR_MUTED

    # Dynamic Page Number
    fld1 = parse_xml(r'<w:fldChar %s w:fldCharType="begin"/>' % nsdecls('w'))
    instr = parse_xml(r'<w:instrText %s xml:space="preserve"> PAGE </w:instrText>' % nsdecls('w'))
    fld2 = parse_xml(r'<w:fldChar %s w:fldCharType="separate"/>' % nsdecls('w'))
    fld3 = parse_xml(r'<w:fldChar %s w:fldCharType="end"/>' % nsdecls('w'))
    r_foot1._r.append(fld1)
    r_foot1._r.append(instr)
    r_foot1._r.append(fld2)
    r_foot1._r.append(fld3)

add_header_footer()

# -------------------------------------------------------------
# Formatting Abstractions
# -------------------------------------------------------------
def add_h1(text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(16)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.font.name = 'Calibri'
    r.font.size = Pt(16)
    r.font.bold = True
    r.font.color.rgb = COLOR_PRIMARY
    return p

def add_h2(text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.font.name = 'Calibri'
    r.font.size = Pt(13)
    r.font.bold = True
    r.font.color.rgb = COLOR_SECONDARY
    return p

def add_h3(text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.font.name = 'Calibri'
    r.font.size = Pt(11.5)
    r.font.bold = True
    r.font.color.rgb = COLOR_DARK
    return p

def add_p(text, bold_prefix="", italic=False):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(5)
    p.paragraph_format.line_spacing = 1.15
    if bold_prefix:
        rb = p.add_run(bold_prefix)
        rb.font.name = 'Calibri'
        rb.font.size = Pt(11)
        rb.font.bold = True
        rb.font.color.rgb = COLOR_DARK
    r = p.add_run(text)
    r.font.name = 'Calibri'
    r.font.size = Pt(11)
    r.font.italic = italic
    r.font.color.rgb = COLOR_TEXT
    return p

def add_bullet(text, bold_prefix=""):
    p = doc.add_paragraph(style='List Bullet')
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.line_spacing = 1.15
    if bold_prefix:
        rb = p.add_run(bold_prefix)
        rb.font.name = 'Calibri'
        rb.font.size = Pt(11)
        rb.font.bold = True
        rb.font.color.rgb = COLOR_DARK
    r = p.add_run(text)
    r.font.name = 'Calibri'
    r.font.size = Pt(11)
    r.font.color.rgb = COLOR_TEXT
    return p

def add_callout(text, title="NOTE / INTEGRITY SAFEGUARD"):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    tbl.columns[0].width = Inches(6.27)
    c = tbl.cell(0, 0)
    set_cell_background(c, "F1F5F9")
    set_cell_margins(c, top=140, bottom=140, left=180, right=180)
    # left thick border
    tcPr = c._tc.get_or_add_tcPr()
    tcBorders = parse_xml(
        f'<w:tcBorders {nsdecls("w")}>'
        f'<w:top w:val="none"/>'
        f'<w:bottom w:val="none"/>'
        f'<w:left w:val="single" w:sz="24" w:space="0" w:color="1B365D"/>'
        f'<w:right w:val="none"/>'
        f'</w:tcBorders>'
    )
    tcPr.append(tcBorders)
    p = c.paragraphs[0]
    p.paragraph_format.space_after = Pt(3)
    r_t = p.add_run(title + "\n")
    r_t.font.name = 'Calibri'
    r_t.font.size = Pt(9.5)
    r_t.font.bold = True
    r_t.font.color.rgb = COLOR_PRIMARY
    r_m = p.add_run(text)
    r_m.font.name = 'Calibri'
    r_m.font.size = Pt(9.5)
    r_m.font.color.rgb = COLOR_TEXT
    doc.add_paragraph().paragraph_format.space_after = Pt(4)

def add_code_block(code_text):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    tbl.columns[0].width = Inches(6.27)
    c = tbl.cell(0, 0)
    set_cell_background(c, "F8FAFC")
    set_cell_margins(c, top=100, bottom=100, left=150, right=150)
    tcPr = c._tc.get_or_add_tcPr()
    tcBorders = parse_xml(
        f'<w:tcBorders {nsdecls("w")}>'
        f'<w:top w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>'
        f'<w:bottom w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>'
        f'<w:left w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>'
        f'<w:right w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>'
        f'</w:tcBorders>'
    )
    tcPr.append(tcBorders)
    p = c.paragraphs[0]
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = 1.05
    r = p.add_run(code_text)
    r.font.name = 'Consolas'
    r.font.size = Pt(8.5)
    r.font.color.rgb = COLOR_DARK
    doc.add_paragraph().paragraph_format.space_after = Pt(4)

def add_figure(image_path, caption, width_inches=5.8):
    if os.path.exists(image_path):
        p_img = doc.add_paragraph()
        p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_img.paragraph_format.space_before = Pt(8)
        p_img.paragraph_format.space_after = Pt(3)
        p_img.add_run().add_picture(image_path, width=Inches(width_inches))
        
        p_cap = doc.add_paragraph()
        p_cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_cap.paragraph_format.space_before = Pt(0)
        p_cap.paragraph_format.space_after = Pt(10)
        r_cap = p_cap.add_run(caption)
        r_cap.font.name = 'Calibri'
        r_cap.font.size = Pt(9.5)
        r_cap.font.italic = True
        r_cap.font.color.rgb = COLOR_MUTED
    else:
        add_callout(f"Image not found on disk: {image_path}\nCaption: {caption}", "IMAGE PLACEHOLDER")

def add_screenshot_box(fig_num, fig_title, filename, console_path, visible_items, redactions):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    tbl.columns[0].width = Inches(6.27)
    c = tbl.cell(0, 0)
    set_cell_background(c, "F8FAFC")
    set_cell_margins(c, top=140, bottom=140, left=180, right=180)
    tcPr = c._tc.get_or_add_tcPr()
    tcBorders = parse_xml(
        f'<w:tcBorders {nsdecls("w")}>'
        f'<w:top w:val="single" w:sz="6" w:space="0" w:color="94A3B8"/>'
        f'<w:bottom w:val="single" w:sz="6" w:space="0" w:color="94A3B8"/>'
        f'<w:left w:val="single" w:sz="18" w:space="0" w:color="0284C7"/>'
        f'<w:right w:val="single" w:sz="6" w:space="0" w:color="94A3B8"/>'
        f'</w:tcBorders>'
    )
    tcPr.append(tcBorders)
    p = c.paragraphs[0]
    p.paragraph_format.space_after = Pt(2)
    r_hdr = p.add_run(f"[VERIFICATION SCREENSHOT PLACEHOLDER — {fig_num}]\n")
    r_hdr.font.name = 'Calibri'
    r_hdr.font.size = Pt(9.5)
    r_hdr.font.bold = True
    r_hdr.font.color.rgb = COLOR_PRIMARY
    
    r_body = p.add_run(
        f"Proposed Caption: {fig_title}\n"
        f"Target Filename: {filename}\n"
        f"Console / CLI Location: {console_path}\n"
        f"Required Visible Evidence: {visible_items}\n"
        f"Redaction Guidance: {redactions}"
    )
    r_body.font.name = 'Calibri'
    r_body.font.size = Pt(8.5)
    r_body.font.color.rgb = COLOR_TEXT
    
    p_cap = doc.add_paragraph()
    p_cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_cap.paragraph_format.space_before = Pt(2)
    p_cap.paragraph_format.space_after = Pt(10)
    r_cap = p_cap.add_run(f"{fig_num}: {fig_title}")
    r_cap.font.name = 'Calibri'
    r_cap.font.size = Pt(9.5)
    r_cap.font.italic = True
    r_cap.font.color.rgb = COLOR_MUTED

# =============================================================
# 1. Title Page
# =============================================================
p_title_dept = doc.add_paragraph()
p_title_dept.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_title_dept.paragraph_format.space_before = Pt(20)
p_title_dept.paragraph_format.space_after = Pt(4)
r_inst = p_title_dept.add_run("VELLORE INSTITUTE OF TECHNOLOGY (VIT), CHENNAI CAMPUS\n")
r_inst.font.name = 'Calibri'
r_inst.font.size = Pt(13)
r_inst.font.bold = True
r_inst.font.color.rgb = COLOR_PRIMARY
r_dept = p_title_dept.add_run("SCHOOL OF COMPUTER SCIENCE AND ENGINEERING (SCOPE)\nDEPARTMENT OF COMPUTER SCIENCE AND ENGINEERING")
r_dept.font.name = 'Calibri'
r_dept.font.size = Pt(10.5)
r_dept.font.color.rgb = COLOR_MUTED

p_rule = doc.add_paragraph()
p_rule.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_rule.paragraph_format.space_before = Pt(12)
p_rule.paragraph_format.space_after = Pt(16)
r_rule = p_rule.add_run("____________________________________________________________________")
r_rule.font.color.rgb = RGBColor(0xCB, 0xD5, 0xE1)

p_maintitle = doc.add_paragraph()
p_maintitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_maintitle.paragraph_format.space_before = Pt(8)
p_maintitle.paragraph_format.space_after = Pt(10)
r_main = p_maintitle.add_run("VIT Chennai Campus AI Digital Twin:\nCloud-Based Campus Occupancy Monitoring and Threshold Alert System")
r_main.font.name = 'Calibri'
r_main.font.size = Pt(22)
r_main.font.bold = True
r_main.font.color.rgb = COLOR_PRIMARY

p_sub = doc.add_paragraph()
p_sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_sub.paragraph_format.space_after = Pt(25)
r_sub = p_sub.add_run("A Formal Final Project Report submitted in partial fulfillment of the requirements\nfor the course Cloud Architecture and Design (CAD)")
r_sub.font.name = 'Calibri'
r_sub.font.size = Pt(11)
r_sub.font.italic = True
r_sub.font.color.rgb = COLOR_SECONDARY

# Metadata Table
meta_tbl = doc.add_table(rows=5, cols=2)
meta_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
meta_tbl.autofit = False
meta_tbl.columns[0].width = Inches(2.2)
meta_tbl.columns[1].width = Inches(4.07)

meta_data = [
    ("Course Code & Title:", "[TEAM ACTION REQUIRED: Insert Course Code, e.g., BCSE308L - Cloud Architecture and Design]"),
    ("Project Team Members:", "[TEAM ACTION REQUIRED: Student 1 Full Name - Reg No, e.g., 22BCE1001]\n[TEAM ACTION REQUIRED: Student 2 Full Name - Reg No, e.g., 22BCE1002]\n[TEAM ACTION REQUIRED: Student 3 Full Name - Reg No, e.g., 22BCE1003]"),
    ("Faculty Supervisor:", "[TEAM ACTION REQUIRED: Faculty Guide Name / Professor Name]"),
    ("Academic Term:", "Fall Semester 2026-2027 (5th Semester B.Tech Computer Science and Engineering)"),
    ("Date of Submission:", "October 30, 2026")
]

for idx, (label, val) in enumerate(meta_data):
    c0 = meta_tbl.cell(idx, 0)
    c1 = meta_tbl.cell(idx, 1)
    set_cell_background(c0, "F8FAFC")
    set_cell_background(c1, "FFFFFF")
    set_cell_margins(c0, top=70, bottom=70, left=100, right=100)
    set_cell_margins(c1, top=70, bottom=70, left=100, right=100)
    
    p0 = c0.paragraphs[0]
    p0.paragraph_format.space_after = Pt(0)
    r0 = p0.add_run(label)
    r0.font.bold = True
    r0.font.size = Pt(9.5)
    r0.font.color.rgb = COLOR_DARK
    
    p1 = c1.paragraphs[0]
    p1.paragraph_format.space_after = Pt(0)
    r1 = p1.add_run(val)
    r1.font.size = Pt(9.5)
    r1.font.color.rgb = COLOR_TEXT

set_table_borders(meta_tbl)

doc.add_paragraph().paragraph_format.space_after = Pt(15)

# Cloud Deployment Badge Table
badge_tbl = doc.add_table(rows=1, cols=1)
badge_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
badge_tbl.autofit = False
badge_tbl.columns[0].width = Inches(6.27)
cb = badge_tbl.cell(0, 0)
set_cell_background(cb, "EFF6FF")
set_cell_margins(cb, top=100, bottom=100, left=140, right=140)
tcPr_b = cb._tc.get_or_add_tcPr()
tcBorders_b = parse_xml(
    f'<w:tcBorders {nsdecls("w")}>'
    f'<w:top w:val="single" w:sz="8" w:space="0" w:color="0284C7"/>'
    f'<w:bottom w:val="single" w:sz="8" w:space="0" w:color="0284C7"/>'
    f'<w:left w:val="single" w:sz="8" w:space="0" w:color="0284C7"/>'
    f'<w:right w:val="single" w:sz="8" w:space="0" w:color="0284C7"/>'
    f'</w:tcBorders>'
)
tcPr_b.append(tcBorders_b)
pb = cb.paragraphs[0]
pb.paragraph_format.space_after = Pt(0)
rb_title = pb.add_run("VERIFIED LIVE AWS DEPLOYMENT METADATA\n")
rb_title.font.bold = True
rb_title.font.size = Pt(9.5)
rb_title.font.color.rgb = RGBColor(0x02, 0x84, 0xC7)
rb_desc = pb.add_run(
    "AWS Account ID: 672791231004  |  Region: ap-south-1 (Mumbai)  |  CLI Profile: vit-deploy\n"
    "CloudFront Production Domain: https://d457wl1fwy7gg.cloudfront.net  (Distribution: E2NGCY20SE2WWQ)\n"
    "API Gateway HTTP API v2: 8iu3rqh0cj  |  DynamoDB Table: vit-campus-telemetry\n"
    "Academic Integrity Statement: All occupancy headcounts and flow rates are simulated CAD demonstration data (isSimulated: true). No physical turnstile hardware is connected."
)
rb_desc.font.size = Pt(8)
rb_desc.font.color.rgb = COLOR_DARK

doc.add_page_break()

# =============================================================
# Table of Contents
# =============================================================
add_h1("Table of Contents")

toc_entries = [
    ("Abstract", "3"),
    ("Keywords", "3"),
    ("1. Introduction", "4"),
    ("    1.1 Motivation & Campus Operational Context", "4"),
    ("    1.2 The Role of 3D Digital Twins in Built Environments", "4"),
    ("    1.3 Cloud-Native Event-Driven Computing vs. Monolithic Approaches", "4"),
    ("    1.4 Project Objectives", "5"),
    ("    1.5 Project Scope & System Boundaries", "5"),
    ("    1.6 Explicit Exclusions & Academic Integrity Statement", "5"),
    ("2. Existing Studies, Tools, and Research Comparison", "6"),
    ("    2.1 Theoretical Foundations of Digital Twins & Built Environments", "6"),
    ("    2.2 IoT Occupancy Sensing & Smart Campus Architectures", "6"),
    ("    2.3 Serverless & Event-Driven Cloud Paradigms", "6"),
    ("    2.4 Topological Graph Optimization in Campus Evacuation", "6"),
    ("    2.5 Detailed Literature Comparison Table (Table 1)", "7"),
    ("    2.6 Differentiation and Technical Position of this Project", "7"),
    ("3. Requirements and Proposed Framework", "8"),
    ("    3.1 Functional Requirements (FR)", "8"),
    ("    3.2 Non-Functional Requirements (NFR)", "8"),
    ("    3.3 High-Level System Architecture (Figure 1)", "9"),
    ("    3.4 Mathematical Formulation of Capacity Utilization & Safety Tiers", "9"),
    ("    3.5 Topological Campus Graph & Evacuation Egress Model", "10"),
    ("4. Implementation and Procedural Workflow", "11"),
    ("    4.1 Repository Organization & Component Architecture", "11"),
    ("    4.2 Telemetry Ingestion via AWS IoT Core & Topic Rules Engine", "11"),
    ("    4.3 Serverless Business Logic in AWS Lambda", "12"),
    ("    4.4 DynamoDB Single-Table Schema & Atomic Transactions (TransactWriteItems)", "12"),
    ("    4.5 Amazon API Gateway HTTP API v2 Ingress & Rate Throttling", "13"),
    ("    4.6 Global Edge Delivery via S3 and CloudFront with Origin Access Control (OAC)", "13"),
    ("5. Experimental Setup", "14"),
    ("    5.1 Test Environment & Hardware Specifications", "14"),
    ("    5.2 Target AWS Account & Regional Configuration", "14"),
    ("    5.3 Provisioned Cloud Resources Inventory (Table 2)", "14"),
    ("    5.4 Test Scenarios & Synthetic Input Parameters (Table 3)", "15"),
    ("6. Results and Discussion", "16"),
    ("    6.1 Demonstration Execution Overview (scripts/demo.ps1)", "16"),
    ("    6.2 Deep Dive: High Occupancy Threshold Alert Scenario (Verified Live Run)", "16"),
    ("    6.3 Scenario Comparison Analysis (Figures 2 & 3)", "17"),
    ("    6.4 Latency & Pipeline Verification Analysis (Figure 4, Table 4)", "18"),
    ("    6.5 Topological Egress Evacuation Analysis (Figure 5)", "19"),
    ("    6.6 Evaluation of Cloud Features: Scalability, Latency, and Cost Impact", "19"),
    ("    6.7 Discussion: What the Experimental Results Establish vs. What They Do Not", "20"),
    ("7. Screenshots and AWS Evidence", "21"),
    ("    7.1 Overview of Verification Evidence", "21"),
    ("    7.2 Embedded User Interface References (Figures 6 & 7)", "21"),
    ("    7.3 AWS Console & Runtime Evidence Register (Figures 8 - 15)", "22"),
    ("8. Discussion of Cloud Characteristics", "24"),
    ("    8.1 Serverless Execution Paradigm", "24"),
    ("    8.2 Event-Driven Decoupled Architecture", "24"),
    ("    8.3 Managed NoSQL Storage & Single-Table Design", "24"),
    ("    8.4 Separation of Frontend and Backend Concerns", "24"),
    ("    8.5 Observability & Operational Resilience", "25"),
    ("    8.6 Security Boundaries, CORS, and Least Privilege IAM", "25"),
    ("    8.7 Financial Analysis & Free-Tier Suitability", "25"),
    ("9. Conclusion and Future Work", "26"),
    ("    9.1 Summary of Built System and Demonstrated Capabilities", "26"),
    ("    9.2 Limitations of Current Implementation", "26"),
    ("    9.3 Proposed Future Work", "26"),
    ("10. References", "27"),
    ("Appendices", "28"),
    ("    Appendix A: Live Demonstration Runbook & CLI Verification Commands", "28"),
    ("    Appendix B: Scenario Definition Matrix & Payload Schemas", "29"),
    ("    Appendix C: Campus Graph & Dijkstra Egress Optimization Details", "30"),
    ("    Appendix D: Demonstration Verification Checklist", "30")
]

toc_tbl = doc.add_table(rows=len(toc_entries), cols=2)
toc_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
toc_tbl.autofit = False
toc_tbl.columns[0].width = Inches(5.5)
toc_tbl.columns[1].width = Inches(0.77)

for idx, (title, page) in enumerate(toc_entries):
    c0 = toc_tbl.cell(idx, 0)
    c1 = toc_tbl.cell(idx, 1)
    set_cell_background(c0, "FFFFFF" if idx % 2 == 0 else "F8FAFC")
    set_cell_background(c1, "FFFFFF" if idx % 2 == 0 else "F8FAFC")
    set_cell_margins(c0, top=30, bottom=30, left=60, right=60)
    set_cell_margins(c1, top=30, bottom=30, left=60, right=60)
    
    p0 = c0.paragraphs[0]
    p0.paragraph_format.space_after = Pt(0)
    r0 = p0.add_run(title)
    r0.font.size = Pt(9.5)
    if not title.startswith("    "):
        r0.font.bold = True
        r0.font.color.rgb = COLOR_PRIMARY
    else:
        r0.font.color.rgb = COLOR_TEXT
        
    p1 = c1.paragraphs[0]
    p1.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    p1.paragraph_format.space_after = Pt(0)
    r1 = p1.add_run(page)
    r1.font.size = Pt(9.5)
    r1.font.color.rgb = COLOR_MUTED

set_table_borders(toc_tbl, sz="2")

doc.add_page_break()

# =============================================================
# Abstract & Keywords
# =============================================================
add_h1("Abstract")
add_p(
    "Modern educational institutions operate high-capacity gathering venues—such as auditoriums, examination halls, "
    "and indoor sports complexes—that experience rapid, non-linear pedestrian congestion during public convocations, symposiums, "
    "and cultural events. Traditional campus crowd monitoring relies on manual security headcounts, isolated CCTV cameras, and static "
    "emergency evacuation signs posted on walls. These legacy systems suffer from informational silos, delayed bottleneck identification, "
    "and an inability to dynamically calculate egress safety risks."
)
add_p(
    "This project presents the VIT Chennai Campus AI Digital Twin, an interactive spatial-cloud system that pairs a 3D WebGL digital twin "
    "of the 36-building VIT Chennai campus with an event-driven serverless cloud backend on Amazon Web Services (AWS). The core backend "
    "architecture centers on the 2,400-seat Mahatma Gandhi Auditorium (Building024). The system implements dual telemetry ingestion pipelines: "
    "an edge turnstile simulator publishing lightweight MQTT messages via AWS IoT Core and an IoT Topic Rule (vit_campus_telemetry_rule), "
    "and an administrative web client issuing debounced HTTPS requests through Amazon API Gateway HTTP API v2 (vit-telemetry-api). "
    "Telemetry payloads are ingested by an AWS Lambda function (vit-telemetry-handler) executed on the arm64 Graviton2 architecture under Node.js 22.x. "
    "Lambda enforces Server-Authoritative Derivation, independently computing venue capacity utilization (U = Occupancy / Capacity * 100) and evaluating "
    "safety tiers (LOW, MODERATE, HIGH, OVERCAPACITY). When occupancy reaches >= 80% (1,920 seats), Lambda triggers an automated VENUE_THRESHOLD_ALARM, "
    "emits structured JSON audit logs into Amazon CloudWatch, and atomically commits both a hot operational state (sk = 'LATEST') and an immutable "
    "time-series audit record (sk = 'TS#<ISO>') to Amazon DynamoDB (vit-campus-telemetry) using ACID transactions (TransactWriteItems)."
)
add_p(
    "Static 3D campus assets—including a 20.3 MB GLTF model (vit_map.glb)—are stored privately in Amazon S3 and distributed globally via "
    "Amazon CloudFront (d457wl1fwy7gg.cloudfront.net) using Origin Access Control (OAC). The client application renders the dynamic operational state, "
    "shifting the auditorium mesh tint to alert amber/orange upon threshold breach, and calculates topological evacuation egress paths across 278 real waypoints "
    "and 606 directed edges using Dijkstra's shortest-path algorithm. Live experimental demonstration of a high-occupancy surge (2,150 attendees / 89.6% utilization) "
    "achieved end-to-end verification across CloudFront, IoT MQTT publication, atomic DynamoDB persistence, and CloudWatch alarm logging in 7.88 seconds. "
    "The entire architecture operates strictly within serverless pay-as-you-go bounds, incurring $0.00 while idle."
)

p_kw = doc.add_paragraph()
p_kw.paragraph_format.space_before = Pt(8)
p_kw.paragraph_format.space_after = Pt(14)
r_kwh = p_kw.add_run("Keywords: ")
r_kwh.font.bold = True
r_kwh.font.color.rgb = COLOR_PRIMARY
r_kwt = p_kw.add_run("Digital Twin, Serverless Computing, AWS IoT Core, AWS Lambda, Amazon DynamoDB, Cloud Architecture, Capacity Threshold Alerting, Pedestrian Telemetry, Dijkstra Egress Routing.")
r_kwt.font.italic = True

doc.add_page_break()

# =============================================================
# 1. Introduction
# =============================================================
add_h1("1. Introduction")

add_h2("1.1 Motivation & Campus Operational Context")
add_p(
    "University campuses are dynamic urban microcosms. Large multi-tier auditoriums, lecture theatre complexes, and sports arenas host thousands "
    "of students, faculty, and external visitors simultaneously. During peak events—such as annual convocations, inter-university cultural festivals, "
    "and unified placement examinations—pedestrian traffic surges rapidly. In an auditorium with a design capacity of 2,400 attendees, a sudden influx "
    "of attendees through turnstiles can elevate utilization from a nominal 60% to near-capacity (85–90%) within minutes."
)
add_p(
    "Under conventional operational workflows, facility administrators discover localized bottlenecks only after physical crowding has saturated "
    "entrance vestibules, blocked egress corridors, or created fire-code violations. Campus navigation remains static: emergency exit placards indicate "
    "fixed geographical paths without accounting for real-time corridor congestion, stairwell blockages, or venue overcrowding. There is an urgent operational "
    "requirement for integrated, near-real-time campus monitoring systems capable of bridging physical space, cloud analytics, and spatial visualization."
)

add_h2("1.2 The Role of 3D Digital Twins in Built Environments")
add_p(
    "A Digital Twin is a dynamic digital representation of a physical asset, process, or system that mirrors its real-world counterpart through "
    "continuous telemetry feeds, analytical modeling, and spatial rendering. While building information modeling (BIM) historically provided static "
    "architectural geometry for construction, a true digital twin integrates live temporal data into the spatial model."
)
add_p("In campus management, a 3D digital twin provides:")
add_bullet("Facilities managers, campus security, and event organizers observe a synchronized, authoritative 3D view of all campus structures.", "1. Shared Operational Picture: ")
add_bullet("Rather than parsing rows of raw database numbers, operators immediately spot localized anomalies through intuitive color-coded spatial alerting (e.g., green for nominal operations, amber/orange for capacity warning, and flashing red for overcapacity).", "2. Contextual Hazard Visualization: ")
add_bullet("Integrating graph-based routing algorithms (e.g., Dijkstra's algorithm) directly into the twin enables dynamic calculation of evacuation egress times and pedestrian dispersal routes tailored to instantaneous venue crowds.", "3. Dynamic Emergency Dispatch: ")

add_h2("1.3 Cloud-Native Event-Driven Computing vs. Monolithic Approaches")
add_p(
    "Traditional digital twin and facility management platforms are built on monolithic client-server architectures: dedicated on-premises servers "
    "or persistently running Virtual Private Servers (VPS) host database daemons, HTTP web servers (Apache/Nginx), and background polling workers. "
    "This paradigm presents severe drawbacks for academic and municipal environments: high 24/7 idle infrastructure costs, scaling bottlenecks during "
    "event crowd bursts, and high operational maintenance overhead."
)
add_p(
    "Cloud-native Serverless Architecture radically disrupts this model. By decomposing the backend into event-driven managed services—managed MQTT message "
    "brokering (AWS IoT Core), on-demand stateless compute (AWS Lambda), managed NoSQL storage (Amazon DynamoDB), managed API ingress (Amazon API Gateway), "
    "and global edge caching (Amazon CloudFront)—compute resources execute strictly upon event arrival. When telemetry ceases, resource consumption and "
    "compute costs drop precisely to zero."
)

add_h2("1.4 Project Objectives")
add_p("The primary technical objectives of this project are:")
add_bullet("Architect, deploy, and configure an end-to-end cloud pipeline on AWS in region ap-south-1 using Infrastructure-as-Code principles.", "1. Provision Serverless Cloud Backend: ")
add_bullet("Support both low-overhead IoT MQTT sensor messaging (Path B) for turnstiles and debounced HTTPS API interactions (Path A) for web clients.", "2. Dual-Ingestion Event Pipelines: ")
add_bullet("Guarantee that venue capacity limits, utilization percentages, and safety threshold classifications are calculated authoritatively by serverless compute, rejecting forged or invalid client payloads.", "3. Server-Authoritative Derivation: ")
add_bullet("Utilize ACID transactions in Amazon DynamoDB (TransactWriteItems) to simultaneously update live operational state and append immutable historical audit entries with automated Time-To-Live (TTL).", "4. Atomic Dual-State Persistence: ")
add_bullet("Configure automated metric extraction from structured JSON logs, establish multi-tier CloudWatch alarms, and compile an operational monitoring dashboard.", "5. Comprehensive Cloud Observability: ")
add_bullet("Deploy a high-fidelity WebGL/Three.js digital twin of the VIT Chennai campus served over global edge CDN infrastructure with client-side topological shortest-path egress routing.", "6. Immersive Spatial 3D Digital Twin: ")

add_h2("1.5 Project Scope & System Boundaries")
add_p(
    "The operational boundaries of this project encompass the 36-building physical campus of Vellore Institute of Technology, Chennai, centered on the "
    "Mahatma Gandhi Auditorium (Building024, capacity 2,400). Cloud infrastructure is provisioned under AWS Account 672791231004 in the Mumbai region (ap-south-1). "
    "Topological routing evaluates 278 real waypoints and 606 directed road/pedestrian edges derived from the campus Wayfinder platform."
)

add_h2("1.6 Explicit Exclusions & Academic Integrity Statement")
add_callout(
    "To maintain absolute academic and scientific integrity, the following boundaries are formally stated:\n"
    "1. No Physical Hardware Turnstiles: Physical optical gates, RFID turnstiles, laser break-beam sensors, and edge microcontrollers (ESP32 / Raspberry Pi) were not physically procured or wired to campus gates.\n"
    "2. Synthetic Demonstration Telemetry: All incoming telemetry events are synthetically generated using a validated PowerShell edge simulation engine (publish_sensor_sim.ps1) or browser-based UI simulation sliders.\n"
    "3. Enforced Server Disclaimers: Every database item written to DynamoDB and every JSON payload emitted by the API contains an immutable attribute 'isSimulated': true and an explicit disclaimer string: 'Simulated CAD demonstration data. Physical IoT turnstile integration pending.' This flag cannot be overridden or removed by client requests.",
    "ACADEMIC INTEGRITY DISCLOSURE & CODE-ENFORCED DISCLAIMER"
)

doc.add_page_break()

# =============================================================
# 2. Existing Studies, Tools, and Research Comparison
# =============================================================
add_h1("2. Existing Studies, Tools, and Research Comparison")

add_h2("2.1 Theoretical Foundations of Digital Twins & Built Environments")
add_p(
    "The conceptual foundation of the digital twin was originally formulated in aerospace and industrial manufacturing for product lifecycle management (PLM). "
    "In recent years, the paradigm has transitioned into civil engineering and smart cities. Batty [1] established that digital twins for built environments "
    "differ fundamentally from CAD blueprints: while computer-aided design represents static geometry, a digital twin reflects continuous temporal dynamics. "
    "Batty emphasized that the utility of an urban digital twin lies in its ability to simulate operational scenarios, detect threshold anomalies, and visualize "
    "future states in near real time."
)

add_h2("2.2 IoT Occupancy Sensing & Smart Campus Architectures")
add_p(
    "Occupancy detection in smart buildings has been widely investigated across diverse sensor modalities. Tekler and Low [2] conducted an exhaustive empirical "
    "review of occupancy tracking technologies, classifying sensing architectures into device-free indirect sensing (PIR, CO2), device-bound sensing (BLE beacons, Wi-Fi), "
    "and portal ingress/egress sensing (optical turnstiles). They identified turnstile counting as the gold standard for high-capacity venue safety because it directly "
    "measures physical ingress and egress boundaries with low cumulative error."
)
add_p(
    "Khajenasiri et al. [3] surveyed IoT protocols for smart city applications, demonstrating that lightweight publish-subscribe protocols (such as MQTT) outperform "
    "HTTP REST protocols by a factor of 10 to 50 in bandwidth efficiency when streaming frequent sensor readings over bandwidth-constrained edge networks. "
    "Shafique et al. [4] further proved that broker-mediated MQTT architectures provide superior resilience in dense sensor networks because edge publishers are fully "
    "decoupled from back-pressure spikes in downstream cloud processing."
)

add_h2("2.3 Serverless & Event-Driven Cloud Paradigms")
add_p(
    "The emergence of Function-as-a-Service (FaaS) and serverless computing represents a major shift in cloud systems engineering. Baldini et al. [5] characterized "
    "serverless computing through three defining properties: stateless ephemeral compute, auto-scaling managed entirely by the cloud provider, and a granular sub-second "
    "billing model. In their analysis of cloud event models, they demonstrated that serverless architectures provide ideal cost-to-performance curves for bursty, sporadic "
    "workloads—precisely the profile of campus event venues."
)
add_p(
    "The AWS Well-Architected Framework for Serverless Applications [6] and AWS Prescriptive Guidance for Event-Driven Architectures [7] formalize industry best practices "
    "for serverless IoT workloads: decouple edge publishers from compute using managed message brokers (AWS IoT Core) and declarative rules engines; enforce least-privilege "
    "IAM execution roles for micro-functions; protect serverless backends against denial-of-service via API Gateway token-bucket stage throttling; and implement single-table "
    "NoSQL designs in DynamoDB with composite partition-sort keys to support predictable, sub-10ms transactional writes."
)

add_h2("2.4 Topological Graph Optimization in Campus Evacuation")
add_p(
    "Optimal emergency egress planning relies on topological graph analysis. Dijkstra [8] formulated the classic single-source shortest-path algorithm for weighted graphs. "
    "In spatial digital twins, pedestrian walkways, building corridors, and emergency exit doors are modeled as a directed graph G = (V, E), where vertices V represent "
    "physical intersections or portal waypoints, and edges E represent road segments weighted by metric length. By combining Dijkstra's algorithm with dynamic venue crowd data, "
    "evacuation planning transitions from static wall signs to dynamic, crowd-aware egress guidance."
)

add_h2("2.5 Detailed Literature Comparison Table")
add_p(
    "Table 1 provides a structured comparative analysis of authoritative peer-reviewed studies, cloud architecture frameworks, and algorithm foundations relative to the "
    "VIT Chennai Campus AI Digital Twin implementation."
)

p_t1_cap = doc.add_paragraph()
p_t1_cap.paragraph_format.space_before = Pt(8)
p_t1_cap.paragraph_format.space_after = Pt(2)
p_t1_cap.paragraph_format.keep_with_next = True
r_t1_cap = p_t1_cap.add_run("Table 1: Comparison of Relevant Existing Studies, Tools, and Architectural Frameworks")
r_t1_cap.font.bold = True
r_t1_cap.font.size = Pt(9.5)
r_t1_cap.font.color.rgb = COLOR_PRIMARY

# Table 1: Literature Comparison
lit_rows = [
    ("Study / Tool", "Year", "Problem Addressed", "Method / Architecture", "Capabilities / Findings", "Limitation / Gap vs. Our Project", "Source Citation"),
    ("Batty", "2018", "Urban digital twin modeling", "Mathematical & GIS simulation", "Theoretical definitions of urban digital twins", "Purely theoretical; lacks serverless cloud architecture", "[1] DOI: 10.1177/2399808318777263"),
    ("Tekler & Low", "2020", "Occupancy tracking accuracy", "Sensor evaluation (PIR, BLE, Turnstiles)", "Turnstiles identified as gold standard for large venues", "Evaluates sensors only; lacks cloud backend and 3D twin", "[2] DOI: 10.1016/j.buildenv.2020.107096"),
    ("Khajenasiri et al.", "2017", "IoT protocol overhead", "Protocol benchmark (MQTT vs HTTP)", "MQTT exhibits 10x-50x lower overhead for edge telemetry", "Evaluates transport only; lacks serverless compute/DB", "[3] DOI: 10.1016/j.egypro.2017.03.239"),
    ("Shafique et al.", "2020", "Dense IoT broker scaling", "Broker architecture survey", "Broker decoupling protects backends from edge surges", "Broad IoT review; lacks spatial 3D visualization", "[4] DOI: 10.1109/ACCESS.2020.2970118"),
    ("Baldini et al.", "2017", "Serverless FaaS execution", "Micro-benchmark evaluation", "Proves sub-second FaaS cost efficiency for bursty loads", "General FaaS research; no campus twin integration", "[5] DOI: 10.1007/978-981-10-5026-8_1"),
    ("AWS Well-Arch.", "2024", "Serverless lens best practices", "Architecture review across 5 pillars", "Standardizes least-privilege IAM and managed NoSQL", "General whitepaper; requires campus domain adaptation", "[6] AWS Whitepapers (Online)"),
    ("AWS Event-Driven", "2024", "Decoupled cloud event patterns", "Prescriptive guidance for IoT & FaaS", "Establishes async MQTT processing via topic rules", "Enterprise guidance; lacks WebGL client integration", "[7] AWS Prescriptive Guidance"),
    ("Dijkstra", "1959", "Minimum-cost path routing", "Combinatorial graph search (O(V^2))", "Computes mathematically optimal shortest evacuation paths", "Static graph formulation; lacks dynamic crowd inputs", "[8] DOI: 10.1007/BF01386390"),
    ("VIT Campus Twin (This Work)", "2026", "Unified campus occupancy, alerting & egress", "Serverless AWS (IoT Core, Lambda, DynamoDB) + WebGL Twin", "Dual MQTT/HTTPS ingestion, atomic dual-state, 3D WebGL twin, Dijkstra evacuation", "Relies on synthetic edge telemetry pending physical turnstiles", "Implemented on AWS Account 672791231004")
]

t1 = doc.add_table(rows=len(lit_rows), cols=7)
t1.alignment = WD_TABLE_ALIGNMENT.CENTER
t1.autofit = False
col_widths = [Inches(0.9), Inches(0.45), Inches(0.95), Inches(0.95), Inches(1.15), Inches(1.1), Inches(0.77)]
for row in t1.rows:
    for i, w in enumerate(col_widths):
        row.cells[i].width = w

for r_idx, row_data in enumerate(lit_rows):
    for c_idx, val in enumerate(row_data):
        cell = t1.cell(r_idx, c_idx)
        if r_idx == 0:
            set_cell_background(cell, "1B365D")
        elif r_idx == len(lit_rows) - 1:
            set_cell_background(cell, "EFF6FF")
        else:
            set_cell_background(cell, "FFFFFF" if r_idx % 2 == 1 else "F8FAFC")
        set_cell_margins(cell, top=50, bottom=50, left=50, right=50)
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(val)
        r.font.size = Pt(7.5)
        if r_idx == 0:
            r.font.bold = True
            r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        elif r_idx == len(lit_rows) - 1:
            r.font.bold = True
            r.font.color.rgb = COLOR_PRIMARY
        else:
            r.font.color.rgb = COLOR_TEXT

set_table_borders(t1, sz="2")

add_h2("2.6 Differentiation and Technical Position of this Project")
add_p(
    "Unlike prior studies that focused strictly on sensor hardware [2], theoretical urban definitions [1], or generic enterprise cloud patterns [6], "
    "this project achieves an end-to-end integration: it links lightweight MQTT edge transport to a serverless compute core, enforces server-authoritative "
    "safety derivations, guarantees dual-state database atomicity (TransactWriteItems), and directly powers an interactive in-browser 3D WebGL spatial model."
)

doc.add_page_break()

# =============================================================
# 3. Requirements and Proposed Framework
# =============================================================
add_h1("3. Requirements and Proposed Framework")

add_h2("3.1 Functional Requirements (FR)")
add_bullet("The system shall accept telemetry through two independent channels: asynchronous MQTT messages over TLS 1.2 on topic vit/campus/Building024/telemetry, and debounced HTTPS POST requests via Amazon API Gateway.", "FR-01 (Dual Ingestion): ")
add_bullet("The backend compute layer shall independently validate incoming payload schemas, enforce venue capacity constraints from an authoritative catalog, calculate utilization percentage (U), and assign safety tiers (LOW, MODERATE, HIGH, OVERCAPACITY).", "FR-02 (Server-Authoritative Derivation): ")
add_bullet("When venue utilization reaches or exceeds the critical safety threshold (>= 80%), the system shall trigger a VENUE_THRESHOLD_ALARM, output structured warning audit logs, increment a dedicated CloudWatch metric, and activate visual alert states across connected digital twin clients.", "FR-03 (Automated Threshold Alerting): ")
add_bullet("Every accepted telemetry event shall be committed atomically to Amazon DynamoDB in a single transaction that updates the current operational snapshot (sk = 'LATEST') and appends an immutable time-series audit record (sk = 'TS#<ISO>') with an automated 7-day Time-To-Live (ttl_epoch).", "FR-04 (Atomic State Persistence): ")
add_bullet("The 3D digital twin web application shall poll the operational snapshot every 5 seconds, updating HUD statistics, changing the 3D building mesh alert color tint, and updating crowd gauges without requiring page refreshes.", "FR-05 (Real-Time State Polling & Visualization): ")
add_bullet("The client twin shall model campus roads and pathways as a topological graph (278 waypoints, 606 directed edges) and compute shortest-path evacuation corridors and door discharge times based on instantaneous venue occupancy.", "FR-06 (Topological Evacuation Egress Routing): ")

add_h2("3.2 Non-Functional Requirements (NFR)")
add_bullet("Ingestion, computation, and database commitment via AWS Lambda shall complete within 200 ms under normal operational conditions.", "NFR-01 (Sub-Second Processing Latency): ")
add_bullet("All backend components shall be 100% serverless, guaranteeing high availability without requiring operating system maintenance or virtual machine management.", "NFR-02 (High Availability & Zero Server Maintenance): ")
add_bullet("The Lambda execution role shall adhere strictly to the Principle of Least Privilege, restricting DynamoDB operations solely to the specific project table and CloudWatch logs to its dedicated function log group. S3 public access shall be completely blocked, permitting asset downloads exclusively through CloudFront Origin Access Control (OAC).", "NFR-03 (Security & Least Privilege): ")
add_bullet("The public HTTP API Gateway endpoint shall enforce stage throttling capped at a sustained rate of 10 requests/second with a burst ceiling of 20 requests.", "NFR-04 (Denial-of-Service & Runaway Loop Protection): ")
add_bullet("The cloud architecture shall leverage on-demand, pay-as-you-go pricing tiers (DynamoDB PAY_PER_REQUEST, AWS Lambda, API Gateway HTTP API v2, and CloudFront), incurring $0.00 while in an idle operational state.", "NFR-05 (Zero-Idle Financial Cost): ")
add_bullet("Every record written to cloud storage and emitted via HTTP APIs shall contain an immutable server-enforced flag 'isSimulated': true accompanied by an explicit academic disclaimer.", "NFR-06 (Academic Integrity Enforcement): ")

add_h2("3.3 High-Level System Architecture")
add_p(
    "Figure 1 illustrates the complete four-layer serverless architecture implemented on AWS, showing dual telemetry ingestion pipelines, "
    "server-authoritative processing in Lambda, atomic ACID persistence in DynamoDB, structured observability in CloudWatch, and secure static edge "
    "delivery via CloudFront and S3."
)

add_figure("docs/figures/fig01_system_architecture.png", "Figure 1: Complete End-to-End Serverless Architecture Diagram illustrating dual ingestion paths, serverless compute, atomic DynamoDB persistence, CloudWatch observability, and CloudFront edge delivery.", width_inches=6.0)

add_h2("3.4 Mathematical Formulation of Capacity Utilization & Safety Tiers")
add_p("Venue capacity utilization is computed dynamically on the server using integer-rounded tenths of a percent:")
add_code_block("utilization (%) = round( (occupancy / capacity) * 100, 1 )")

add_p("The safety classification engine maps the calculated utilization U to four distinct operational tiers:")
add_code_block(
    "Status(U) = \n"
    "  LOW          if U < 50.0%         (Emerald Green #10b981, Nominal Operations)\n"
    "  MODERATE     if 50.0% <= U < 80.0% (Amber #eab308, Steady Attendance)\n"
    "  HIGH         if 80.0% <= U <= 100% (Warning Orange #f97316, Near-Capacity Warning)\n"
    "  OVERCAPACITY if U > 100.0%        (Flashing Red #ef4444, Critical Hazard)\n\n"
    "ThresholdAlert(U) = true if U >= 80.0% else false"
)

add_h2("3.5 Topological Campus Graph & Evacuation Egress Model")
add_p(
    "The physical campus road and pedestrian network is modeled as a weighted directed graph G = (V, E) with |V| = 278 physical waypoints and "
    "|E| = 606 directed edges. Egress discharge time across the auditorium's 6 designated double-door emergency portals (discharge constant "
    "R_flow = 70 persons/min per lane, total discharge rate = 420 persons/min) is modeled as:"
)
add_code_block("T_egress (minutes) = N_occupancy / (L_portals * R_flow) = N_occupancy / 420.0")

doc.add_page_break()

# =============================================================
# 4. Implementation and Procedural Workflow
# =============================================================
add_h1("4. Implementation and Procedural Workflow")

add_h2("4.1 Repository Organization & Component Architecture")
add_p(
    "The implementation is partitioned across three core tiers: backend serverless functions (backend/lambda/), cloud Infrastructure-as-Code "
    "deployment and demonstration scripts (scripts/), and the 3D WebGL digital twin frontend (src/ and public/)."
)

add_h2("4.2 Telemetry Ingestion via AWS IoT Core & Topic Rules Engine")
add_p(
    "Edge turnstile simulation publishes to topic vit/campus/Building024/telemetry over TLS 1.2 at the regional ATS endpoint. "
    "The AWS IoT Rules Engine evaluates topic rule vit_campus_telemetry_rule (SQL: SELECT * FROM 'vit/campus/Building024/telemetry') and invokes "
    "Lambda asynchronously via resource-based execution permissions."
)

add_h2("4.3 Serverless Business Logic in AWS Lambda")
add_p(
    "AWS Lambda function vit-telemetry-handler (Node.js 22.x, arm64 Graviton2) serves as the central compute brain. It validates payload schemas, "
    "enforces authorized venue capacity limits from VENUE_CATALOG, derives utilization, assigns safety tiers, outputs structured JSON logs to CloudWatch, "
    "and commits atomic transactions to DynamoDB."
)

add_h2("4.4 DynamoDB Single-Table Schema & Atomic Transactions (TransactWriteItems)")
add_p(
    "Amazon DynamoDB table vit-campus-telemetry utilizes a single-table composite key design (Partition Key venueId, Sort Key sk). "
    "Lambda commits two items simultaneously via TransactWriteItems: the hot operational state snapshot (sk = 'LATEST') and an immutable "
    "historical audit record (sk = 'TS#<ISO>') with an automated 7-day Time-To-Live (ttl_epoch)."
)
add_code_block(
    "// Sample Atomic Dual-Write Item Structure:\n"
    "Item 1 (Hot State):     { venueId: 'Building024', sk: 'LATEST', occupancy: 2150, utilization: 89.6, status: 'HIGH', thresholdAlert: true, isSimulated: true }\n"
    "Item 2 (Audit History): { venueId: 'Building024', sk: 'TS#2026-10-30T06:30:00Z', occupancy: 2150, ttl_epoch: 1793860200, isSimulated: true }"
)

add_h2("4.5 Amazon API Gateway HTTP API v2 Ingress & Rate Throttling")
add_p(
    "Amazon API Gateway HTTP API v2 (vit-telemetry-api / 8iu3rqh0cj) exposes public HTTPS endpoints for web polling (GET /telemetry/latest) and UI simulation "
    "(POST /telemetry). Stage throttling on $default enforces a sustained rate limit of 10 req/s and a burst ceiling of 20 req/s to prevent DDoS or runaway client loops."
)

add_h2("4.6 Global Edge Delivery via S3 and CloudFront with Origin Access Control (OAC)")
add_p(
    "The 20.3 MB 3D campus model (vit_map.glb) and static WebGL bundles reside in private S3 bucket vit-chennai-digital-twin-672791231004. Direct public bucket access "
    "is blocked. Amazon CloudFront distribution E2NGCY20SE2WWQ (d457wl1fwy7gg.cloudfront.net) delivers content globally over HTTPS with Origin Access Control (OAC)."
)

doc.add_page_break()

# =============================================================
# 5. Experimental Setup
# =============================================================
add_h1("5. Experimental Setup")

add_h2("5.1 Test Environment & Hardware Specifications")
add_p("Verification testing was conducted on a Windows workstation running PowerShell 5.1 with AWS CLI v2 and Node.js:")
add_bullet("Windows 11 Enterprise (x86_64)", "Workstation OS: ")
add_bullet("Windows PowerShell 5.1 (powershell.exe)", "Terminal Shell: ")
add_bullet("aws-cli/2.x with profile vit-deploy", "AWS CLI: ")
add_bullet("Node.js 22.x (nodejs22.x) on AWS Lambda (arm64 Graviton2)", "Backend Compute: ")
add_bullet("Vite 6.4.4, Three.js 0.170.0, Node.js 20.x", "Frontend Build: ")

add_h2("5.2 Target AWS Account & Regional Configuration")
add_bullet("672791231004", "AWS Account ID: ")
add_bullet("ap-south-1 (Asia Pacific - Mumbai)", "Target Region: ")
add_bullet("vit-deploy (IAM User: vit-digital-twin-deploy)", "CLI Profile: ")

add_h2("5.3 Provisioned Cloud Resources Inventory")
add_p("Table 2 documents all provisioned cloud infrastructure resources deployed in AWS Account 672791231004.")

p_t2_cap = doc.add_paragraph()
p_t2_cap.paragraph_format.space_before = Pt(8)
p_t2_cap.paragraph_format.space_after = Pt(2)
p_t2_cap.paragraph_format.keep_with_next = True
r_t2_cap = p_t2_cap.add_run("Table 2: Inventory of Deployed Cloud Infrastructure Resources")
r_t2_cap.font.bold = True
r_t2_cap.font.size = Pt(9.5)
r_t2_cap.font.color.rgb = COLOR_PRIMARY

res_rows = [
    ("Service", "Resource Identifier", "Physical Name / ARN", "Configuration Details", "Operational Role"),
    ("AWS IoT Core", "IoT Thing", "vit-campus-auditorium-sensor-01", "Attributes: venueId=Building024", "Represents physical turnstile sensor array"),
    ("AWS IoT Core", "IoT Policy", "vit-campus-sensor-policy", "Scoped iot:Publish, iot:Connect", "Enforces least-privilege edge device authorization"),
    ("AWS IoT Core", "Topic Rule", "vit_campus_telemetry_rule", "SQL: SELECT * FROM 'vit/campus/...' ", "Evaluates MQTT topics and triggers Lambda"),
    ("AWS Lambda", "Function", "vit-telemetry-handler", "Runtime: Node.js 22.x, arm64, 128 MB", "Validates telemetry, calculates utilization, writes DDB"),
    ("AWS IAM", "Role", "vit-telemetry-lambda-role", "Scoped policy vit-telemetry-access", "Authorizes Lambda access strictly to DDB & CloudWatch"),
    ("Amazon DynamoDB", "Table", "vit-campus-telemetry", "PK: venueId (S), SK: sk (S), TTL enabled", "Stores hot state (LATEST) and audit history (TS#)"),
    ("Amazon API Gateway", "HTTP API v2", "vit-telemetry-api (8iu3rqh0cj)", "Stage: $default, Rate: 10/s, Burst: 20", "Public HTTPS ingress for web polling and UI slider"),
    ("Amazon S3", "Private Bucket", "vit-chennai-digital-twin-672791231004", "Block Public Access: ON (All 4 settings)", "Stores 3D model, static HTML, CSS, JS assets"),
    ("Amazon CloudFront", "Distribution", "E2NGCY20SE2WWQ", "Domain: d457wl1fwy7gg.cloudfront.net", "Global edge caching & HTTPS termination via OAC"),
    ("Amazon CloudWatch", "Log Group", "/aws/lambda/vit-telemetry-handler", "7-day retention policy", "Centralized structured JSON audit log aggregation"),
    ("Amazon CloudWatch", "Metric Filter", "vit-high-occupancy-filter", "Pattern: { $.event = 'VENUE_THRESHOLD_ALARM' }", "Extracts metric HighOccupancyAlerts from logs"),
    ("Amazon CloudWatch", "Dashboard", "vit-campus-digital-twin-dashboard", "4-widget unified operational grid", "Real-time administrative monitoring screen")
]

t2 = doc.add_table(rows=len(res_rows), cols=5)
t2.alignment = WD_TABLE_ALIGNMENT.CENTER
t2.autofit = False
col_widths_t2 = [Inches(1.1), Inches(1.1), Inches(1.6), Inches(1.2), Inches(1.27)]
for row in t2.rows:
    for i, w in enumerate(col_widths_t2):
        row.cells[i].width = w

for r_idx, row_data in enumerate(res_rows):
    for c_idx, val in enumerate(row_data):
        cell = t2.cell(r_idx, c_idx)
        set_cell_background(cell, "1B365D" if r_idx == 0 else ("FFFFFF" if r_idx % 2 == 1 else "F8FAFC"))
        set_cell_margins(cell, top=50, bottom=50, left=50, right=50)
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(val)
        r.font.size = Pt(7.5)
        if r_idx == 0:
            r.font.bold = True
            r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        else:
            r.font.color.rgb = COLOR_TEXT

set_table_borders(t2, sz="2")

add_h2("5.4 Test Scenarios & Synthetic Input Parameters")
add_p("Table 3 outlines the three primary demonstration scenarios evaluated by the orchestrator script.")

p_t3_cap = doc.add_paragraph()
p_t3_cap.paragraph_format.space_before = Pt(8)
p_t3_cap.paragraph_format.space_after = Pt(2)
p_t3_cap.paragraph_format.keep_with_next = True
r_t3_cap = p_t3_cap.add_run("Table 3: Demonstration Scenario Definitions & Expected Classifications")
r_t3_cap.font.bold = True
r_t3_cap.font.size = Pt(9.5)
r_t3_cap.font.color.rgb = COLOR_PRIMARY

sc_rows = [
    ("Scenario Name", "Headcount", "Capacity", "Flow Delta", "Expected Util.", "Expected Tier", "Threshold Alert", "Operational Context"),
    ("Normal Operations", "1,480", "2,400", "+0 p/min", "61.7%", "MODERATE", "false", "Standard lecture; nominal crowd flow."),
    ("Convocation Surge (High)", "2,150", "2,400", "+25 p/min", "89.6%", "HIGH", "true", "Major symposium rush; trips threshold alarm, turns twin amber."),
    ("Critical Overcapacity", "2,450", "2,400", "+40 p/min", "102.1%", "OVERCAPACITY", "true", "Fest overcrowding; triggers critical red alert."),
    ("Reset Baseline", "1,480", "2,400", "+0 p/min", "61.7%", "MODERATE", "false", "Restores baseline nominal state after testing.")
]

t3 = doc.add_table(rows=len(sc_rows), cols=8)
t3.alignment = WD_TABLE_ALIGNMENT.CENTER
t3.autofit = False
col_widths_t3 = [Inches(1.1), Inches(0.65), Inches(0.6), Inches(0.65), Inches(0.75), Inches(0.8), Inches(0.65), Inches(1.07)]
for row in t3.rows:
    for i, w in enumerate(col_widths_t3):
        row.cells[i].width = w

for r_idx, row_data in enumerate(sc_rows):
    for c_idx, val in enumerate(row_data):
        cell = t3.cell(r_idx, c_idx)
        set_cell_background(cell, "1B365D" if r_idx == 0 else ("FFFFFF" if r_idx % 2 == 1 else "F8FAFC"))
        set_cell_margins(cell, top=50, bottom=50, left=50, right=50)
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(val)
        r.font.size = Pt(7.5)
        if r_idx == 0:
            r.font.bold = True
            r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        else:
            r.font.color.rgb = COLOR_TEXT

set_table_borders(t3, sz="2")

doc.add_page_break()

# =============================================================
# 6. Results and Discussion
# =============================================================
add_h1("6. Results and Discussion")

add_h2("6.1 Demonstration Execution Overview (scripts/demo.ps1)")
add_p(
    "Validation was executed via scripts/demo.ps1. The script sequentially executes CloudFront reachability verification, "
    "IoT MQTT telemetry publication, DynamoDB atomic polling using a temporary JSON key file, and CloudWatch structured log retrieval."
)

add_h2("6.2 Deep Dive: High Occupancy Threshold Alert Scenario (Verified Live Run)")
add_p(
    "A live demonstration of the High Scenario surge was executed on the live cloud infrastructure. The complete observed output is recorded below:"
)
add_code_block(
    "Command: powershell -ExecutionPolicy Bypass -File .\\scripts\\demo.ps1 -Demo -Scenario High\n\n"
    "[Step 1/4] Checking live CloudFront digital twin reachability...\n"
    "  -> Live CloudFront site and AWS profile 'vit-deploy' verified [PASS in 420ms]\n\n"
    "[Step 2/4] Publishing deterministic telemetry to AWS IoT Core MQTT...\n"
    "  -> Ingested via AWS IoT ATS Endpoint (HTTPS/MQTT) [PASS in 185ms]\n\n"
    "[Step 3/4] Polling DynamoDB LATEST state to verify atomic persistence...\n"
    "  -> DynamoDB item 'Building024' (sk: LATEST) verified [PASS in 1420ms]\n"
    "     Persisted: Occupancy=2150, Utilization=89.6%, Status=HIGH, SensorSource=IOT_MQTT_TURNSTILE\n\n"
    "[Step 4/4] Inspecting CloudWatch structured audit log...\n"
    "  -> CloudWatch Log Stream: /aws/lambda/vit-telemetry-handler [PASS in 1180ms]\n"
    "     Latest Event: {\"level\":\"WARN\",\"event\":\"VENUE_THRESHOLD_ALARM\",\"source\":\"AWS_IOT_CORE\",\"venueId\":\"Building024\",\"occupancy\":2150,\"capacity\":2400,\"utilization\":89.6,\"status\":\"HIGH\",\"alertTriggered\":true,\"sensorSource\":\"IOT_MQTT_TURNSTILE\"}\n\n"
    "DEMONSTRATION SCENARIO COMPLETE: HIGH OCCUPANCY THRESHOLD ALERT\n"
    "Live Occupancy: 2150 / 2400 seats (89.6% utilization) | System Status: HIGH [ALARM ACTIVE]\n"
    "Total Execution Time: 7.88s"
)

add_h2("6.3 Scenario Comparison Analysis (Figures 2 & 3)")
add_p(
    "Figures 2 and 3 present the headcount comparison and capacity utilization percentages across the demonstration scenarios relative to the "
    "80% warning threshold (1,920 seats) and 100% design capacity limit (2,400 seats)."
)

add_figure("docs/figures/fig02_occupancy_scenarios.png", "Figure 2: Headcount comparison across Normal, High, and Overcapacity scenarios plotted against the 80% warning threshold (1,920 seats) and 100% design capacity limit (2,400 seats).", width_inches=5.2)
add_figure("docs/figures/fig03_utilization_tiers.png", "Figure 3: Server-authoritative capacity utilization percentages and safety tier classifications across demonstration scenarios.", width_inches=5.2)

add_h2("6.4 Latency & Pipeline Verification Analysis (Figure 4, Table 4)")
add_p(
    "The total observed execution duration for the live High Scenario was 7.88 seconds. Figure 4 depicts the observed latency breakdown, "
    "and Table 4 details the verification verdicts across the integrated cloud pipeline."
)

add_figure("docs/figures/fig04_e2e_latency_breakdown.png", "Figure 4: Latency breakdown across the four demonstration stages during the live High Scenario execution run (Total elapsed time: 7.88 seconds).", width_inches=5.2)

p_t4_cap = doc.add_paragraph()
p_t4_cap.paragraph_format.space_before = Pt(8)
p_t4_cap.paragraph_format.space_after = Pt(2)
p_t4_cap.paragraph_format.keep_with_next = True
r_t4_cap = p_t4_cap.add_run("Table 4: Step-by-Step Test Verdicts & Observed Verification Metrics")
r_t4_cap.font.bold = True
r_t4_cap.font.size = Pt(9.5)
r_t4_cap.font.color.rgb = COLOR_PRIMARY

ver_rows = [
    ("Step", "Component Tested", "Target Resource", "Observed Latency", "Verdict", "Concrete Evidence Logged"),
    ("1/4", "CloudFront CDN Reachability", "d457wl1fwy7gg.cloudfront.net", "420 ms", "PASS", "HTTPS status 200; distribution E2NGCY20SE2WWQ deployed"),
    ("2/4", "AWS IoT Core MQTT Ingestion", "Topic vit/campus/.../telemetry", "185 ms", "PASS", "Exit code 0 returned by aws iot-data publish via ATS endpoint"),
    ("3/4", "DynamoDB Atomic Persistence", "Table vit-campus-telemetry", "1,420 ms", "PASS", "Item Building024 verified with occupancy: 2150, utilization: 89.6"),
    ("4/4", "CloudWatch Observability Log", "Group /aws/lambda/vit-...", "1,180 ms", "PASS", "Log event captured matching $.event = 'VENUE_THRESHOLD_ALARM'"),
    ("Total", "Full End-to-End Pipeline", "All 4 Integrated Cloud Services", "7.88 s", "PASS", "Complete automated verification across edge, compute, DB, & logs")
]

t4 = doc.add_table(rows=len(ver_rows), cols=6)
t4.alignment = WD_TABLE_ALIGNMENT.CENTER
t4.autofit = False
col_widths_t4 = [Inches(0.6), Inches(1.2), Inches(1.3), Inches(0.8), Inches(0.6), Inches(1.77)]
for row in t4.rows:
    for i, w in enumerate(col_widths_t4):
        row.cells[i].width = w

for r_idx, row_data in enumerate(ver_rows):
    for c_idx, val in enumerate(row_data):
        cell = t4.cell(r_idx, c_idx)
        if r_idx == 0:
            set_cell_background(cell, "1B365D")
        elif r_idx == len(ver_rows) - 1:
            set_cell_background(cell, "EFF6FF")
        else:
            set_cell_background(cell, "FFFFFF" if r_idx % 2 == 1 else "F8FAFC")
        set_cell_margins(cell, top=50, bottom=50, left=50, right=50)
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(val)
        r.font.size = Pt(7.5)
        if r_idx == 0:
            r.font.bold = True
            r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        elif r_idx == len(ver_rows) - 1:
            r.font.bold = True
            r.font.color.rgb = COLOR_PRIMARY
        else:
            r.font.color.rgb = COLOR_TEXT

set_table_borders(t4, sz="2")

add_h2("6.5 Topological Egress Evacuation Analysis (Figure 5)")
add_p(
    "Figure 5 depicts the topological evacuation discharge curve across the 6 double-door egress portals. Egress time scales linearly from "
    "3 minutes 31 seconds at baseline (1,480 attendees) to 5 minutes 7 seconds during the demonstrated High Scenario surge (2,150 attendees), "
    "reaching 5 minutes 43 seconds at full capacity (2,400 attendees)."
)

add_figure("docs/figures/fig05_egress_discharge_model.png", "Figure 5: Topological evacuation egress time (minutes) as a function of attendee occupancy across Mahatma Gandhi Auditorium's 6 emergency exit portals.", width_inches=5.2)

add_h2("6.6 Evaluation of Cloud Features: Scalability, Latency, and Cost Impact")
add_bullet("Because API Gateway, Lambda, and DynamoDB are serverless, concurrent traffic surges from thousands of students viewing the campus map do not cause server contention. S3 bandwidth is shielded by CloudFront edge caching.", "Scalability: ")
add_bullet("Core serverless processing in AWS Lambda executed within ~125 ms. DynamoDB single-digit millisecond latency ensured the updated operational state was detectable by external polling within 1.4 seconds.", "Latency: ")
add_bullet("Under AWS Free Tier allowances (1,000,000 Lambda requests/month, 25 GB DynamoDB storage, 1 TB CloudFront data transfer), running this entire digital twin infrastructure costs $0.00/month. When idle, zero compute instances are charged.", "Cost Impact: ")

add_h2("6.7 Discussion: What the Experimental Results Establish vs. What They Do Not")
add_bullet("The results definitively prove that the event-driven serverless cloud architecture functions as designed. Sensor telemetry published over MQTT is successfully routed by topic rules, processed by serverless compute, evaluated against capacity thresholds, committed atomically to DynamoDB, tracked via CloudWatch logs, and visualized in real time on the 3D twin canvas.", "What Is Proven: ")
add_bullet("The results do not prove physical turnstile hardware accuracy, physical optical beam reliability, or biometric identification. The system's inputs represent validated synthetic demonstration data.", "What Is Not Proven: ")

doc.add_page_break()

# =============================================================
# 7. Screenshots and AWS Evidence
# =============================================================
add_h1("7. Screenshots and AWS Evidence")

add_h2("7.1 Overview of Verification Evidence")
add_p(
    "To ensure transparency and academic credibility, this report maintains a strict distinction between Resource Allocation / Configuration Evidence "
    "(proving that cloud infrastructure is real and properly configured) and Runtime Execution Evidence (proving that data was processed and alarms "
    "triggered during testing)."
)

add_h2("7.2 Embedded User Interface References")
add_p("Figures 6 and 7 show the production user interface of the 3D Digital Twin application.")

add_figure("docs/figures/fig14_campus_explorer_ui.png", "Figure 6: Live 3D Digital Twin 'Campus Explorer' interface featuring the searchable campus directory on the left, interactive Three.js 3D campus in the center, and structure information card on the right.", width_inches=5.6)
add_figure("docs/figures/fig15_auditorium_twin_ui.png", "Figure 7: Dedicated Mahatma Gandhi Auditorium Digital Twin view showing real-time occupancy HUD gauges, capacity presets, crowd flow deltas, and emergency evacuation egress indicators.", width_inches=5.6)

add_h2("7.3 AWS Console & Runtime Evidence Register")
add_p(
    "The following structured verification placeholders specify the exact AWS Management Console and local terminal evidence required to finalize the submission. "
    "Refer to docs/SCREENSHOT_ACTION_REGISTER.md for prioritized capture workflows."
)

add_screenshot_box(
    "Figure 8", "Amazon DynamoDB Live Operational Snapshot (sk = 'LATEST')",
    "docs/figures/fig07_dynamodb_latest.png",
    "AWS Console -> DynamoDB -> Tables -> vit-campus-telemetry -> Explore items",
    "venueId='Building024', sk='LATEST', occupancy=2150, utilization=89.6, status='HIGH', thresholdAlert=true, sensorSource='IOT_MQTT_TURNSTILE', isSimulated=true.",
    "Mask 12-digit AWS Account ID in top navigation bar (optional)."
)

add_screenshot_box(
    "Figure 9", "Amazon CloudWatch Structured Alarm Log Event (VENUE_THRESHOLD_ALARM)",
    "docs/figures/fig08_cloudwatch_alarm_log.png",
    "AWS Console -> CloudWatch -> Log groups -> /aws/lambda/vit-telemetry-handler",
    "Single-line JSON log expanded showing 'level':'WARN', 'event':'VENUE_THRESHOLD_ALARM', 'venueId':'Building024', 'occupancy':2150.",
    "Mask internal AWS Request ID if desired."
)

add_screenshot_box(
    "Figure 10", "AWS IoT Core Thing & Active X.509 Certificate Attachments",
    "docs/figures/fig02_iot_thing.png",
    "AWS Console -> AWS IoT Core -> Manage -> Things -> vit-campus-auditorium-sensor-01",
    "Thing Name, Thing ARN, attributes (venueId: Building024), active X.509 certificate attached.",
    "Mask certificate ID hash string (retain first 8 characters)."
)

add_screenshot_box(
    "Figure 11", "AWS IoT Topic Rule SQL & Target AWS Lambda Action",
    "docs/figures/fig03_iot_rule.png",
    "AWS Console -> AWS IoT Core -> Message routing -> Rules -> vit_campus_telemetry_rule",
    "Rule Name, status 'Enabled', SQL: SELECT * FROM 'vit/campus/Building024/telemetry', Action: Send a message to a Lambda function: vit-telemetry-handler.",
    "None."
)

add_screenshot_box(
    "Figure 12", "AWS Lambda Runtime & Environment Configuration (Node.js 22.x, arm64)",
    "docs/figures/fig04_lambda_config.png",
    "AWS Console -> Lambda -> Functions -> vit-telemetry-handler",
    "Runtime: Node.js 22.x, Architecture: arm64, Memory: 128 MB, Role: vit-telemetry-lambda-role, Triggers: API Gateway and AWS IoT.",
    "None."
)

add_screenshot_box(
    "Figure 13", "Amazon API Gateway HTTP API v2 Routes & Stage Throttling",
    "docs/figures/fig06_api_gateway_routes.png",
    "AWS Console -> API Gateway -> vit-telemetry-api -> Routes & Stages ($default)",
    "Routes (GET /telemetry/latest, POST /telemetry), Stage Throttling (Rate: 10 req/s, Burst: 20 req/s), CORS configuration.",
    "None."
)

add_screenshot_box(
    "Figure 14", "Amazon CloudFront Distribution Overview & Origin Access Control (OAC)",
    "docs/figures/fig13_cloudfront_distribution.png",
    "AWS Console -> CloudFront -> Distributions -> E2NGCY20SE2WWQ",
    "Domain: d457wl1fwy7gg.cloudfront.net, Status: Deployed, Origin: S3 with Origin Access Control (OAC) enabled.",
    "None."
)

add_screenshot_box(
    "Figure 15", "Amazon CloudWatch Unified Operational Monitoring Dashboard",
    "docs/figures/fig09_cloudwatch_dashboard.png",
    "AWS Console -> CloudWatch -> Dashboards -> vit-campus-digital-twin-dashboard",
    "4-widget grid: Invocations & Errors, Duration & Throttles, High Occupancy Alarms, DynamoDB Consumed Capacity.",
    "None."
)

doc.add_page_break()

# =============================================================
# 8. Discussion of Cloud Characteristics
# =============================================================
add_h1("8. Discussion of Cloud Characteristics")

add_h2("8.1 Serverless Execution Paradigm")
add_p(
    "By executing business logic on AWS Lambda, the application eliminates server management entirely. Compute resources are provisioned on demand "
    "in milliseconds and terminated immediately upon completion of the request. Utilizing the arm64 Graviton2 architecture delivers an estimated 20% "
    "improvement in price-performance over traditional x86_64 architectures."
)

add_h2("8.2 Event-Driven Decoupled Architecture")
add_p(
    "The system decouples edge sensor ingestion from database writes via AWS IoT Core and the IoT Rules Engine. Turnstiles publish to a lightweight MQTT broker "
    "without waiting for database transactions to commit. If downstream database writes experience transient throttling, the message broker buffers incoming events, "
    "preventing edge network disconnections."
)

add_h2("8.3 Managed NoSQL Storage & Single-Table Design")
add_p(
    "DynamoDB's single-table design (vit-campus-telemetry) avoids the latency and resource overhead of relational table joins. By partitioning data on venueId "
    "and utilizing sort key prefixes (LATEST and TS#<ISO>), the application performs both point-in-time operational state retrieval and historical time-series queries "
    "with consistent single-digit millisecond latency. Native Time-To-Live (TTL) automatically purges stale audit items after 7 days without incurring database compute write charges."
)

add_h2("8.4 Separation of Frontend and Backend Concerns")
add_p(
    "The 3D WebGL client is completely decoupled from the cloud backend. The frontend bundle is compiled statically and distributed via global CDN edge caches. "
    "It accesses cloud resources exclusively through sanitized HTTPS endpoints (Amazon API Gateway) discovered at runtime via public/config.json. This guarantees "
    "that frontend code changes never require backend redeployments, and backend scaling never impairs web asset delivery."
)

add_h2("8.5 Observability & Operational Resilience")
add_p(
    "CloudWatch provides complete observability across the serverless lifecycle. Structured single-line JSON logging allows metric filters to parse operational anomalies "
    "(VENUE_THRESHOLD_ALARM) and publish metrics to custom namespaces (VITChennai/DigitalTwin). Three automated alarms ensure that if Lambda errors exceed 0, "
    "invocations are throttled, or high-occupancy surges occur, operators are immediately notified."
)

add_h2("8.6 Security Boundaries, CORS, and Least Privilege IAM")
add_p("Security is enforced across all architectural boundaries:")
add_bullet("Lambda operates under execution role vit-telemetry-lambda-role, restricted strictly to writing CloudWatch logs and accessing table vit-campus-telemetry. It possesses zero access to S3 or VPC resources.", "1. Least-Privilege IAM Roles: ")
add_bullet("S3 objects cannot be fetched via direct URLs. Only CloudFront is authorized to read objects using cryptographic Origin Access Control (OAC) signing.", "2. S3 Block Public Access & OAC: ")
add_bullet("API Gateway and Lambda enforce strict Cross-Origin Resource Sharing (CORS), restricting browser requests to https://d457wl1fwy7gg.cloudfront.net and authorized local development hosts.", "3. CORS Hardening: ")
add_bullet("API Gateway stage throttling (10 req/s, burst 20) ensures that denial-of-service attempts or recursive client loops cannot exceed free-tier boundaries.", "4. Token-Bucket Throttling: ")

add_h2("8.7 Financial Analysis & Free-Tier Suitability")
add_p(
    "The entire architecture was designed to fit within the AWS Free Tier (1,000,000 Lambda requests/month, 25 GB DynamoDB storage, 1 TB CloudFront data transfer). "
    "During normal operational demonstration cycles, the project incurs approximately $0.00/month, proving exceptional economic efficiency for academic and municipal campus deployments."
)

doc.add_page_break()

# =============================================================
# 9. Conclusion and Future Work
# =============================================================
add_h1("9. Conclusion and Future Work")

add_h2("9.1 Summary of Built System and Demonstrated Capabilities")
add_p(
    "The VIT Chennai Campus AI Digital Twin successfully demonstrates a modern, scalable, event-driven serverless architecture on Amazon Web Services. "
    "The project connects a rich 3D geospatial digital twin of the VIT Chennai campus with a real-time serverless backend deployed in the ap-south-1 region."
)
add_p("Key verified outcomes include:")
add_bullet("Full automated deployment across AWS IoT Core, Lambda, DynamoDB, API Gateway, S3, CloudFront, and CloudWatch under account 672791231004.", "1. Live Cloud Integration: ")
add_bullet("Demonstration of both low-overhead MQTT edge sensor publishing and debounced HTTPS web client updates.", "2. Dual-Path Ingestion: ")
add_bullet("Rigorous server-side derivation of capacity utilization and automated threshold alerting at >= 80% occupancy.", "3. Server-Authoritative Safety Evaluation: ")
add_bullet("Atomic dual-item commits (LATEST hot state + TS# historical audit) in Amazon DynamoDB.", "4. ACID Transactional Persistence: ")
add_bullet("Client-side topological evacuation routing across 278 waypoints and 606 edges using Dijkstra's algorithm.", "5. Dynamic Egress Routing: ")

add_h2("9.2 Limitations of Current Implementation")
add_p(
    "The primary technical limitation of the current work is the reliance on synthetically generated edge telemetry. While the cloud pipeline, "
    "database transactions, alerting systems, and 3D visualization are 100% real and deployed live on AWS, physical optical turnstiles and edge microcontrollers "
    "were not installed at the campus auditorium entrance."
)

add_h2("9.3 Proposed Future Work")
add_bullet("Deploy ESP32 or Raspberry Pi microcontrollers integrated with bidirectional optical break-beam sensors or RFID smart-card readers at each auditorium entrance lane.", "1. Physical Edge Device Deployment: ")
add_bullet("Flash each edge microcontroller with unique X.509 private keys and certificates generated via AWS IoT Core for hardware-level mutual TLS (mTLS) authentication.", "2. Hardware X.509 Certificate Authentication: ")
add_bullet("Configure CloudWatch alarm actions to publish to an Amazon Simple Notification Service (SNS) topic, automatically dispatching SMS alerts and emails to campus security personnel during threshold breaches.", "3. Automated Notification Integration (Amazon SNS): ")
add_bullet("Train time-series forecasting models (e.g., DeepAR or ARIMA) on accumulated DynamoDB historical audit records to forecast crowd congestion 30 minutes before major campus events commence.", "4. Predictive Machine Learning Forecasting (Amazon SageMaker): ")

doc.add_page_break()

# =============================================================
# 10. References
# =============================================================
add_h1("10. References")

references = [
    "[1] M. Batty, \"Digital twins for smart cities,\" Environment and Planning B: Urban Analytics and City Science, vol. 45, no. 5, pp. 817–820, 2018. DOI: 10.1177/2399808318777263.",
    "[2] Z. D. Tekler and R. Low, \"IoT-based occupancy tracking in smart buildings: A comprehensive review of sensors, communication protocols, and processing techniques,\" Building and Environment, vol. 182, p. 107096, 2020. DOI: 10.1016/j.buildenv.2020.107096.",
    "[3] I. Khajenasiri, A. Estebsari, M. Verhelst, and G. Gielen, \"A review on Internet of Things solutions for intelligent energy control in buildings for smart city applications,\" Energy Procedia, vol. 111, pp. 770–779, 2017. DOI: 10.1016/j.egypro.2017.03.239.",
    "[4] K. Shafique, B. A. Khawaja, F. Sabir, S. Qazi, and M. Mustaqim, \"Internet of Things (IoT) for next-generation smart systems: A review of current challenges, future trends and solutions for extreme conditions,\" IEEE Access, vol. 8, pp. 27476–27498, 2020. DOI: 10.1109/ACCESS.2020.2970118.",
    "[5] I. Baldini, P. Castro, K. Chang, P. Cheng, S. Fink, V. Ishakian, N. Mitchell, V. Muthusamy, R. Rabbah, A. Slominski, and P. Suter, \"Serverless computing: Current trends and open problems,\" in Research Advances in Cloud Computing, Springer, 2017, pp. 1–20. DOI: 10.1007/978-981-10-5026-8_1.",
    "[6] Amazon Web Services, \"AWS Well-Architected Framework: Serverless Applications Lens,\" AWS Whitepapers, Seattle, WA, 2024. [Online]. Available: https://docs.aws.amazon.com/wellarchitected/latest/serverless-applications-lens/",
    "[7] Amazon Web Services, \"Designing Event-Driven Architectures on AWS,\" AWS Prescriptive Guidance, Seattle, WA, 2024. [Online]. Available: https://docs.aws.amazon.com/prescriptive-guidance/latest/event-driven-architecture/",
    "[8] E. W. Dijkstra, \"A note on two problems in connexion with graphs,\" Numerische Mathematik, vol. 1, no. 1, pp. 269–271, 1959. DOI: 10.1007/BF01386390."
]

for ref in references:
    p_ref = doc.add_paragraph()
    p_ref.paragraph_format.left_indent = Inches(0.4)
    p_ref.paragraph_format.first_line_indent = Inches(-0.4)
    p_ref.paragraph_format.space_after = Pt(4)
    p_ref.paragraph_format.line_spacing = 1.15
    r = p_ref.add_run(ref)
    r.font.name = 'Calibri'
    r.font.size = Pt(9.5)
    r.font.color.rgb = COLOR_TEXT

doc.add_page_break()

# =============================================================
# Appendices
# =============================================================
add_h1("Appendices")

add_h2("Appendix A: Live Demonstration Runbook & CLI Verification Commands")
add_p("1. Pre-Demo Read-Only Health Check (run 2 minutes before the demonstration):")
add_code_block("powershell -ExecutionPolicy Bypass -File .\\scripts\\demo.ps1 -Check")

add_p("2. Primary Professor Demonstration (High Scenario Surge):")
add_code_block("powershell -ExecutionPolicy Bypass -File .\\scripts\\demo.ps1 -Demo -Scenario High")

add_p("3. Direct AWS CLI Verification Commands (to satisfy committee skepticism):")
add_code_block(
    "# Verify DynamoDB LATEST Item:\n"
    "aws dynamodb get-item --table-name vit-campus-telemetry \\\n"
    "  --key '{\"venueId\":{\"S\":\"Building024\"},\"sk\":{\"S\":\"LATEST\"}}' \\\n"
    "  --region ap-south-1 --profile vit-deploy --output json\n\n"
    "# Verify Structured CloudWatch Threshold Alarm Log:\n"
    "aws logs filter-log-events --log-group-name /aws/lambda/vit-telemetry-handler \\\n"
    "  --filter-pattern '{ $.event = \"VENUE_THRESHOLD_ALARM\" }' \\\n"
    "  --limit 3 --region ap-south-1 --profile vit-deploy --output json\n\n"
    "# Verify CloudFront Distribution Status:\n"
    "aws cloudfront get-distribution --id E2NGCY20SE2WWQ \\\n"
    "  --profile vit-deploy --query \"Distribution.Status\" --output text"
)

add_h2("Appendix B: Scenario Definition Matrix & Payload Schemas")
add_p("Ingested MQTT Telemetry Payload Schema:")
add_code_block(
    "{\n"
    "  \"venueId\": \"Building024\",\n"
    "  \"occupancy\": 2150,\n"
    "  \"flowDelta\": 25,\n"
    "  \"sensorSource\": \"IOT_MQTT_TURNSTILE\",\n"
    "  \"timestamp\": \"2026-10-30T06:30:00.000Z\",\n"
    "  \"isSimulated\": true\n"
    "}"
)

add_p("Persisted DynamoDB Hot State Schema (sk = 'LATEST'):")
add_code_block(
    "{\n"
    "  \"venueId\": { \"S\": \"Building024\" },\n"
    "  \"sk\": { \"S\": \"LATEST\" },\n"
    "  \"venueName\": { \"S\": \"Mahatma Gandhi Auditorium\" },\n"
    "  \"capacity\": { \"N\": \"2400\" },\n"
    "  \"occupancy\": { \"N\": \"2150\" },\n"
    "  \"utilization\": { \"N\": \"89.6\" },\n"
    "  \"status\": { \"S\": \"HIGH\" },\n"
    "  \"statusLabel\": { \"S\": \"High Occupancy\" },\n"
    "  \"statusColor\": { \"S\": \"#f97316\" },\n"
    "  \"flowRate\": { \"N\": \"25\" },\n"
    "  \"sensorSource\": { \"S\": \"IOT_MQTT_TURNSTILE\" },\n"
    "  \"thresholdAlert\": { \"BOOL\": true },\n"
    "  \"isSimulated\": { \"BOOL\": true },\n"
    "  \"updatedAt\": { \"S\": \"2026-10-30T06:30:00.125Z\" },\n"
    "  \"disclaimer\": { \"S\": \"Simulated CAD demonstration data. Physical IoT turnstile integration pending.\" }\n"
    "}"
)

add_h2("Appendix C: Campus Graph & Dijkstra Egress Optimization Details")
add_bullet("Total Waypoints (|V|): 278", "Graph Vertices: ")
add_bullet("Total Directed Edges (|E|): 606", "Graph Edges: ")
add_bullet("1,258 / 1,258 (100% connected)", "Pairwise Waypoint Reachability: ")
add_bullet("E Block Hostel (Waypoint 68) to Student Parking 2 (Waypoint 250) = 1,428.2 meters (1,208.9 m pedestrian walking route).", "Campus Topological Diameter: ")
add_bullet("Waypoint 199", "Auditorium Primary Portal: ")
add_bullet("Waypoint 1 (Main Entrance Gate)", "Campus Perimeter Gate 1: ")

add_h2("Appendix D: Demonstration Verification Checklist")
add_bullet("AWS credentials profile vit-deploy authenticated.", "[PASS] ")
add_bullet("CloudFront distribution E2NGCY20SE2WWQ in Deployed state.", "[PASS] ")
add_bullet("DynamoDB table vit-campus-telemetry active with TTL enabled on ttl_epoch.", "[PASS] ")
add_bullet("Lambda function vit-telemetry-handler deployed on Node.js 22.x arm64.", "[PASS] ")
add_bullet("API Gateway HTTP API v2 (8iu3rqh0cj) route integrations and CORS active.", "[PASS] ")
add_bullet("IoT Thing vit-campus-auditorium-sensor-01 registered.", "[PASS] ")
add_bullet("Topic rule vit_campus_telemetry_rule active with Lambda trigger.", "[PASS] ")
add_bullet("3 CloudWatch alarms configured and monitoring dashboard deployed.", "[PASS] ")
add_bullet("S3 bucket vit-chennai-digital-twin-672791231004 private with OAC enabled.", "[PASS] ")
add_bullet("3D campus model (vit_map.glb) loads cleanly over HTTPS.", "[PASS] ")
add_bullet("All 191 regression tests in project test suite passing.", "[PASS] ")

doc.save(OUTPUT_PATH)
print(f"Generated {OUTPUT_PATH} successfully!")
