# Competency Skills

This directory is prepared for domain-specific competency skills.

## What are Competency Skills?

Skills that teach Claude specialized knowledge in specific domains:

- Programming languages (TypeScript, Rust, Python)
- Frameworks (React, Next.js, FastAPI)
- Practices (Security review, Performance optimization)
- Tools (Docker, Kubernetes, Terraform)

## How to Add a Competency Skill

1. Create a directory with the skill name:
   ```
   competencies/typescript-strict/
   ```

2. Add a `SKILL.md` file with frontmatter:
   ```yaml
   ---
   name: typescript-strict
   description: Strict TypeScript patterns. Use when writing TypeScript code.
   ---

   # TypeScript Strict Mode

   ## Guidelines
   - Always use explicit types
   - Avoid `any`
   - Use discriminated unions
   ...
   ```

3. Optionally add supporting files:
   ```
   competencies/typescript-strict/
   ├── SKILL.md
   ├── examples.md
   └── patterns.md
   ```

## Sharing Competency Skills

Competency skills can be:

- **Personal**: `~/.claude/skills/` (your machine only)
- **Project**: `.claude/skills/` (shared via git)
- **Global CWT**: `templates/skills/competencies/` (shared via cwt update)

## Examples to Consider

- `typescript-strict` - Strict TypeScript patterns
- `security-review` - Security vulnerability analysis
- `react-patterns` - Modern React with hooks
- `sql-optimization` - Database query optimization
- `api-design` - RESTful API design principles
- `testing-strategy` - Comprehensive testing approaches
