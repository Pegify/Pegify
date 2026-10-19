# Pegify Marketplace

Public marketplace content for Pegify: skills and plugins that the Pegify PDA,
ZCode, Claude Code, and the `pegify` CLI can browse and install.

This repository is **content only**. It does not contain Pegify application
source code. Application source stays private until a deliberate open-source
decision is made.

## What's here

| Path | Contents |
| --- | --- |
| `.claude-plugin/marketplace.json` | Marketplace catalogue (Claude Code / ZCode / Pegify PDA compatible) |
| `plugins/pegify-skills/` | Pegify's core workflow skills |
| `marketplace/` | Reserved for signed `pegify` CLI registry packages |
| `dist/` | Reserved for built, signed registry artifacts |

## Use it

Pegify PDA / ZCode / Claude Code:

```text
/plugin marketplace add Pegify/Pegify
/plugin install pegify-skills@pegify
```

Or add the catalogue URL directly:

```text
https://raw.githubusercontent.com/Pegify/Pegify/main/.claude-plugin/marketplace.json
```

The Pegify PDA also keeps other marketplaces available alongside this one
(Claude Code, ZCode, and user-added sources). This repository is the Pegify
marketplace entry.

## Skills in this marketplace

| Skill | What it does |
| --- | --- |
| `code-review` | Structured review — correctness, security, readability, coverage |
| `git-workflow` | Branch-first git flow; small commits, PR for every change |
| `pr-description` | Reviewer-ready PR descriptions with concrete test steps |
| `systematic-debugging` | Root-cause discipline before any fix |
| `tdd` | Failing test first, minimal implementation, green commit |
| `writing-plans` | Execution-ready plans with exact paths, commands, output |

## Add or update a skill

```text
plugins/<plugin-name>/
  .claude-plugin/plugin.json
  skills/<skill-name>/SKILL.md
```

`SKILL.md` starts with YAML frontmatter:

```markdown
---
name: skill-name
description: One sentence that tells an agent when to use this skill.
---

Instructions...
```

Then add the plugin to `.claude-plugin/marketplace.json` and open a pull
request.

## Repository rules

- **No application source code, no build tooling, no secrets, no keys.**
- Only marketplace content: `SKILL.md` files, catalogue JSON, manifests, and
  signed `dist/` artifacts.
- `Distribution guard` CI fails any push that adds a path outside the
  allowlist, a key/secret file type, or a file larger than 2 MiB. Publish
  binaries as release assets instead.
- Plugins may reference external services, but never bundle credentials.

## Status

Early. Next up: the signed registry for `pegify market`, then the Pegify
integration plugin for each runtime.
