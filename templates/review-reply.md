# Reply to a Plugin Directory review email

Send from the address on the wordpress.org account that owns the submission. Reply **in
the same thread** — a new thread restarts the queue.

Structure: one block per quoted finding, in the reviewer's own order, each saying *what
changed and where*. Reviewers re-scan the whole tree, so fix **every** occurrence, not only
the lines they quoted — and say that you did.

---

```
Hello,

Thank you for the review. I have addressed every point below and uploaded a new version.

---

1) <Reviewer's heading, quoted verbatim>

   Finding:  <the line or file they quoted>
   Cause:    <one sentence — what was actually wrong>
   Fix:      <what changed>
   Where:    <file:line, or "all N occurrences across the tree">
   Verified: Plugin Check <version>, --mode=new, 0 errors.

2) <next finding>

   …

---

Points where I believe the finding is a false positive
(none, unless listed here — each with its reasoning)

   <file:line> — <sniff code>
   <why the surrounding context makes this line safe, in one or two sentences>
   The annotation in the code reads:
       // phpcs:ignore <Sniff.Code> -- <the same reason>

---

Plugin name and slug

   Desired permalink (slug): <my-plugin>
   Display name:             <My Plugin>

<Include this section whenever naming came up at all. The slug does not follow a
display-name change — state it explicitly. It cannot be changed after approval.>

---

Other changes in this upload
   - <anything you changed that they did not ask for>

The full source, including build tooling, is at <public URL>.

Thank you,
<name>
```

---

## Before sending

- [ ] Every quoted finding has its own numbered block.
- [ ] Every finding says **where**, and confirms *all* occurrences were fixed.
- [ ] Gate 1 re-run on the **new ZIP**, `--mode=new --self-test`: zero errors.
- [ ] Each remaining warning is either fixed or listed above with a justification that
      matches `references/justifying-false-positives.md`.
- [ ] `Contributors:` includes the wordpress.org account that owns the slug.
- [ ] The desired slug is stated explicitly, if naming was raised.
- [ ] Every URL in the readme and headers returns 200.
- [ ] `== External services ==` is present if the plugin makes any remote call.
- [ ] The ZIP contains no `.claude/`, `CLAUDE.md`, `.cursor/`, `.github/`, tests, tooling,
      dotfiles or archives.

## Tone

State what changed. Do not argue guideline interpretation in the first reply — fix it, or
explain the technical constraint in two sentences and offer the alternative you chose.
Reviewers are volunteers working a queue; a reply that reads as a diff gets processed
fastest.
