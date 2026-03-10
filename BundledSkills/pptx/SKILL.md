---
name: pptx
description: "Use this skill any time a .pptx file is involved in any way: creating, reading, editing, or converting PowerPoint presentations."
---

## PPTX Skill

### Quick Reference

| Task | Guide |
|------|-------|
| Read/analyze content | `python -m markitdown presentation.pptx` |
| Edit or create from template | Unpack and edit XML |
| Create from scratch | Use pptxgenjs — see `references/creating-presentations.md` |
| Design ideas | See `references/design-guide.md` |

### Reading Content

```bash
python -m markitdown presentation.pptx
python scripts/thumbnail.py presentation.pptx
python scripts/office/unpack.py presentation.pptx unpacked/
```

### QA (Required)

```bash
python -m markitdown output.pptx
```

### Converting to Images

```bash
python scripts/office/soffice.py --headless --convert-to pdf output.pptx
pdftoppm -jpeg -r 150 output.pdf slide
```

### Dependencies

- `pip install "markitdown[pptx]"` — text extraction
- `pip install Pillow` — thumbnail grids
- `npm install -g pptxgenjs` — creating from scratch
- LibreOffice — PDF conversion
- Poppler (`pdftoppm`) — PDF to images
