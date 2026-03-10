# Skill Format Specification

## SKILL.md Format

```markdown
---
name: my-skill
description: "Clear description of when this skill should be used"
version: 1.0
author: "Author Name"
emoji: "icon"
---

## Instructions for the AI

(Detailed instructions, procedures, code examples, etc.)
```

## Required Fields
- `name`: Skill identifier
- `description`: When to use this skill (critical for triggering)

## Optional Fields
- `version`: Semantic version
- `author`: Creator name
- `emoji`: Display icon
- `compatibility`: Target compatibility info

## Progressive Disclosure
1. Metadata (name + description) — Always visible (~100 words)
2. SKILL.md body — Read when skill triggers (<500 lines ideal)
3. References — Read on demand (unlimited)

## Distribution
Skills are shared as ZIP files containing the skill folder.
Import via McClaw Settings → Skills → Import ZIP.
