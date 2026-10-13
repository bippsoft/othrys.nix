---
name: write-issue
description: Draft a GitHub issue for one defect in the repository's four-heading form. Use when a defect is found that the current change does not fix, or when asked to file one.
metadata:
  opencode/slash: "true"
---

One issue states one defect. Two defects are two issues.

**Title.** A lowercase sentence that states what is wrong, with no type
prefix and no full stop, such as `the signature check fails every pull request opened by Dependabot`.

**Body.** Four headings, 80 to 150 words in all.

```markdown
## Observed

What happens, with the option, the file or the command, and the error text
when there is one.

## Mechanism

Why it happens, naming the file and the code that causes it.

## Fix shape

- The change, as two or three bullets.

## Acceptance

- What is true when the issue is closed, stated so that a check can prove it.
```

**Rules.**

- State the defect as it stands in the tree. Never say how it came to light.
- Use `alice` and `example.com`. Never name a real host, domain or person.
- Name files and options exactly and put them in backticks.
- A breaking fix takes the `breaking` label.

Draft the issue and show it. Open it with `gh issue create` only when asked
to, with the labels and the milestone the request names.
