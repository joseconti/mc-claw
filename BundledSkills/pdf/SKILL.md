---
name: pdf
description: "Use this skill whenever the user wants to do anything with PDF files: create, merge, split, extract text/tables, OCR, watermark, encrypt, or convert."
---

## PDF Processing Guide

### Quick Reference

| Task | Best Tool |
|------|-----------|
| Merge/Split/Rotate | pypdf — see `references/pypdf-operations.md` |
| Extract text | pdfplumber `page.extract_text()` |
| Extract tables | pdfplumber `page.extract_tables()` |
| Create PDFs | reportlab — see `references/creating-pdfs.md` |
| Command line | qpdf, pdftotext — see `references/cli-tools.md` |
| OCR scanned PDFs | pytesseract + pdf2image |
| Watermark/Encrypt | pypdf — see `references/pypdf-operations.md` |

### Quick Start

```python
from pypdf import PdfReader, PdfWriter
reader = PdfReader("document.pdf")
text = ""
for page in reader.pages:
    text += page.extract_text()
```
