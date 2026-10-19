---
name: pr-description
description: Write reviewer-ready pull request descriptions with a concise title, summary, and concrete how-to-test steps.
---

# PR Description

## Title

Under 70 characters. Imperative mood. "Add X" not "Added X" not "Adding X".

## Body structure

```text
## Summary
- [bullet] What changed (the what)
- [bullet] Why it changed (the why — the business/technical reason)

## How to test
- [ ] Step 1 to verify the change works
- [ ] Edge case to check
- [ ] Regression: existing behavior still works because X

## Notes (optional)
Any non-obvious decisions, follow-ups, or things a reviewer should know.
```

## Rules

- No "this PR" — just describe the change directly.
- The why is more important than the what. Reviewers can read the diff.
- Test plan must be concrete steps, not "test the feature".
