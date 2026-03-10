# pypdf Operations

## Merge PDFs
```python
from pypdf import PdfWriter, PdfReader
writer = PdfWriter()
for pdf_file in ["doc1.pdf", "doc2.pdf"]:
    for page in PdfReader(pdf_file).pages:
        writer.add_page(page)
with open("merged.pdf", "wb") as output:
    writer.write(output)
```

## Split PDF
```python
reader = PdfReader("input.pdf")
for i, page in enumerate(reader.pages):
    writer = PdfWriter()
    writer.add_page(page)
    with open(f"page_{i+1}.pdf", "wb") as output:
        writer.write(output)
```

## Rotate Pages
```python
page = PdfReader("input.pdf").pages[0]
page.rotate(90)
writer = PdfWriter()
writer.add_page(page)
with open("rotated.pdf", "wb") as output:
    writer.write(output)
```

## Add Watermark
```python
watermark = PdfReader("watermark.pdf").pages[0]
writer = PdfWriter()
for page in PdfReader("document.pdf").pages:
    page.merge_page(watermark)
    writer.add_page(page)
with open("watermarked.pdf", "wb") as output:
    writer.write(output)
```

## Password Protection
```python
writer = PdfWriter()
for page in PdfReader("input.pdf").pages:
    writer.add_page(page)
writer.encrypt("userpassword", "ownerpassword")
with open("encrypted.pdf", "wb") as output:
    writer.write(output)
```
