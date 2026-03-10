---
name: docx
description: "Use this skill whenever the user wants to create, read, edit, or manipulate Word documents (.docx files). Triggers include: any mention of 'Word doc', 'word document', '.docx', or requests to produce professional documents with formatting like tables of contents, headings, page numbers, or letterheads."
---

## DOCX creation, editing, and analysis

### Overview

A .docx file is a ZIP archive containing XML files.

### Quick Reference

| Task | Approach |
|------|----------|
| Read/analyze content | `pandoc` or unpack for raw XML |
| Create new document | Use `docx-js` — see `references/creating-documents.md` |
| Edit existing document | Unpack → edit XML → repack — see `references/editing-documents.md` |

### Reading Content

```bash
pandoc --track-changes=all document.docx -o output.md
python scripts/office/unpack.py document.docx unpacked/
```

### Converting

```bash
python scripts/office/soffice.py --headless --convert-to docx document.doc  # .doc → .docx
python scripts/office/soffice.py --headless --convert-to pdf document.docx  # .docx → PDF
pdftoppm -jpeg -r 150 document.pdf page                                     # PDF → images
```

### Dependencies

- pandoc: Text extraction
- docx: `npm install -g docx` (new documents)
- LibreOffice: PDF conversion
- Poppler: `pdftoppm` for images
