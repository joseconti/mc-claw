# Creating New Documents with docx-js

Install: `npm install -g docx`

## Setup
```javascript
const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, ImageRun,
        Header, Footer, AlignmentType, PageOrientation, LevelFormat, ExternalHyperlink,
        InternalHyperlink, Bookmark, FootnoteReferenceRun,
        TabStopType, TabStopPosition,
        TableOfContents, HeadingLevel, BorderStyle, WidthType, ShadingType,
        PageNumber, PageBreak } = require('docx');

const doc = new Document({ sections: [{ children: [/* content */] }] });
Packer.toBuffer(doc).then(buffer => fs.writeFileSync("doc.docx", buffer));
```

## Validation
```bash
python scripts/office/validate.py doc.docx
```

## Page Size

```javascript
sections: [{
  properties: {
    page: {
      size: { width: 12240, height: 15840 },  // US Letter in DXA
      margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
    }
  },
  children: [/* content */]
}]
```

| Paper | Width | Height |
|-------|-------|--------|
| US Letter | 12,240 | 15,840 |
| A4 (default) | 11,906 | 16,838 |

Landscape: pass portrait dimensions + `orientation: PageOrientation.LANDSCAPE`.

## Styles
```javascript
const doc = new Document({
  styles: {
    default: { document: { run: { font: "Arial", size: 24 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 32, bold: true, font: "Arial" },
        paragraph: { spacing: { before: 240, after: 240 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 28, bold: true, font: "Arial" },
        paragraph: { spacing: { before: 180, after: 180 }, outlineLevel: 1 } },
    ]
  },
  sections: [{ children: [
    new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Title")] }),
  ]}]
});
```

## Lists (NEVER use unicode bullets)
```javascript
numbering: {
  config: [
    { reference: "bullets",
      levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
    { reference: "numbers",
      levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
  ]
}
```

## Tables
```javascript
const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
new Table({
  width: { size: 9360, type: WidthType.DXA },
  columnWidths: [4680, 4680],
  rows: [new TableRow({ children: [
    new TableCell({ borders, width: { size: 4680, type: WidthType.DXA },
      shading: { fill: "D5E8F0", type: ShadingType.CLEAR },
      children: [new Paragraph({ children: [new TextRun("Cell")] })] })
  ]})]
})
```

## Images
```javascript
new Paragraph({ children: [new ImageRun({
  type: "png", data: fs.readFileSync("image.png"),
  transformation: { width: 200, height: 150 },
  altText: { title: "Title", description: "Desc", name: "Name" }
})]})
```

## Headers/Footers, TOC, Page Breaks, Hyperlinks, Footnotes, Tab Stops, Multi-Column
See the docx-js documentation for full examples of these features.

## Critical Rules
- Set page size explicitly (defaults to A4)
- Never use `\n` — use separate Paragraph elements
- Never use unicode bullets — use LevelFormat.BULLET
- Always set table width with DXA — never WidthType.PERCENTAGE
- Use ShadingType.CLEAR — never SOLID
- Override built-in styles with exact IDs: "Heading1", "Heading2"
- Include outlineLevel for TOC
