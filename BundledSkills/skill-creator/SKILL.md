---
name: skill-creator
description: "Create new skills for McClaw. A skill is a folder with a SKILL.md file and optional references/ folder that teaches the AI specialized knowledge."
---

## Skill Creator

### Skill Structure

```
skill-name/
├── SKILL.md           # Required: YAML frontmatter + instructions
└── references/        # Optional: detailed reference docs
    ├── topic-1.md
    └── topic-2.md
```

### Process
1. Decide what the skill should do
2. Write a draft SKILL.md
3. Test with real prompts
4. Refine based on results
5. Add references/ for detailed content

See `references/skill-format.md` for the full format specification.
See `references/writing-guidelines.md` for best practices.
