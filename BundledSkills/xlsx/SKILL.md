---
name: xlsx
description: "Use this skill any time a spreadsheet file is the primary input or output: creating, editing, or analyzing Excel files."
---

## Excel Spreadsheet Skill

### Quick Reference

| Task | Tool |
|------|------|
| Data analysis, bulk ops | pandas |
| Formulas, formatting | openpyxl — see `references/openpyxl-guide.md` |
| Formatting standards | See `references/formatting-standards.md` |

### CRITICAL: Use Formulas, Not Hardcoded Values

```python
# WRONG
sheet['B10'] = total
# CORRECT
sheet['B10'] = '=SUM(B2:B9)'
```

### Common Workflow
1. Choose tool: pandas for data, openpyxl for formulas/formatting
2. Create/Load workbook
3. Add/edit data, formulas, and formatting
4. Save file
5. Recalculate formulas: `python scripts/recalc.py output.xlsx`
6. Verify and fix errors

### Best Practices
- pandas: Best for data analysis, bulk operations
- openpyxl: Best for complex formatting, formulas
- Cell indices are 1-based
- Use `data_only=True` to read calculated values (Warning: loses formulas)
