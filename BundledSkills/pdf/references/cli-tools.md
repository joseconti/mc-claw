# PDF Command-Line Tools

## pdftotext (poppler-utils)
```bash
pdftotext input.pdf output.txt          # Extract text
pdftotext -layout input.pdf output.txt  # Preserve layout
pdftotext -f 1 -l 5 input.pdf output.txt  # Pages 1-5
```

## qpdf
```bash
qpdf --empty --pages file1.pdf file2.pdf -- merged.pdf  # Merge
qpdf input.pdf --pages . 1-5 -- pages1-5.pdf            # Extract pages
qpdf input.pdf output.pdf --rotate=+90:1                 # Rotate
qpdf --password=mypassword --decrypt encrypted.pdf decrypted.pdf  # Decrypt
```
