# Editing Existing Documents

## Step 1: Unpack
```bash
python scripts/office/unpack.py document.docx unpacked/
```

## Step 2: Edit XML

Edit files in `unpacked/word/`. Use "Claude" as the author for tracked changes and comments.

Use the Edit tool directly for string replacement. Do not write Python scripts.

Use smart quotes for new content:
| Entity | Character |
|--------|-----------|
| `&#x2018;` | ' (left single) |
| `&#x2019;` | ' (right single / apostrophe) |
| `&#x201C;` | " (left double) |
| `&#x201D;` | " (right double) |

## Step 3: Pack
```bash
python scripts/office/pack.py unpacked/ output.docx --original document.docx
```

## XML Reference — Tracked Changes

```xml
<!-- Insertion -->
<w:ins w:id="1" w:author="Claude" w:date="2025-01-01T00:00:00Z">
  <w:r><w:t>inserted text</w:t></w:r>
</w:ins>

<!-- Deletion -->
<w:del w:id="2" w:author="Claude" w:date="2025-01-01T00:00:00Z">
  <w:r><w:delText>deleted text</w:delText></w:r>
</w:del>
```

## Accepting Tracked Changes
```bash
python scripts/accept_changes.py input.docx output.docx
```
