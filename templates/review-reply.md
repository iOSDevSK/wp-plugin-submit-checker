# Reply to a Plugin Directory review email

Send from the address on the wordpress.org account that owns the submission. Reply **in
the same thread** — a new thread, or a reply to the submission confirmation, does not put
you in the reviewer's queue. Upload the fixed ZIP on the "Add your plugin" page **first**,
logged in as the same account, then reply.

## The email is short. The worksheet is not.

The Plugins Team now says it in the review itself:

> Please keep your reply short, direct and clear. Avoid overly verbose and long AI
> responses. **Do not list the changes made**, we don't need that, we will review the entire
> plugin again, we won't compare the changes. However, please share any important context
> or clarifications that may help us during the review.

So the reply carries only what a re-scan **cannot see for itself**:

1. that a new version is uploaded (and its version number);
2. **ownership / naming context** — who owns the brand, where the proof is;
3. the **desired slug**, explicitly, whenever naming came up at all;
4. routes or outputs that are **public or unescaped by design**, one line each;
5. a real question, if you have one.

Nothing else. No per-finding diff, no "Verified with Plugin Check", no thanks paragraph.

---

```
Hello,

I've uploaded <version>, which addresses the points in this review.

<OWNERSHIP — only if name/ownership was raised>
<Pro product name> is my own product, sold at <https://example.com>. The ownership TXT
record (wordpressorg-<username>-verification) is in place on <example.com>. I'd like to
keep the name and the slug "<slug>".
   — or —
I'd like to change the permalink to "<new-slug>" (display name: "<New Name>").

<PUBLIC BY DESIGN — only if such routes/outputs were listed>
Four REST routes are public by design (form submit, block-form submit, double opt-in
confirmation link, "load more" for published posts); each is commented in place with what
protects it.

<QUESTION — only if you have one>

Thank you,
<name>
```

Aim for **under 120 words**. If it reads like a changelog, cut it.

---

## The worksheet (for you — never paste it into the email)

Work through it per quoted finding, in the reviewer's order. They re-scan the whole tree,
so fix **every** occurrence, not only the quoted lines.

```
1) <Reviewer's heading>
   Finding:  <the line or file they quoted>
   Cause:    <one sentence — what was actually wrong>
   Fix:      <what changed>
   Where:    <file:line, or "all N occurrences across the tree">
   Context the reviewer needs: <none | one line that goes into the email>
```

Only the last line of each block can reach the email.

## Before sending

- [ ] The new ZIP is uploaded from the owning account; its version is higher than the one reviewed.
- [ ] **Meaningful progress**: every section of the review is addressed, not a subset. "Updates
      that resolve only a small portion of the reported issues" can get the plugin rejected
      for good.
- [ ] Gate 1 re-run on the **new ZIP**, `--mode=new --self-test`: zero errors.
- [ ] Gate 2 sweeps re-run for every family the email named (`reviewer-findings.md` §10, §11,
      §19–§22) — the greps come back clean or with justified lines only.
- [ ] Ownership: the TXT record resolves (`dig +short TXT <domain>`), or the account email is
      on the brand's domain. The account email is a **real mailbox** that does not bounce.
- [ ] The desired slug is stated explicitly, if naming was raised. Renaming the display name
      alone changes nothing; the slug cannot change after approval.
- [ ] `Contributors:` includes the wordpress.org account that owns the slug.
- [ ] Every URL in the readme and headers returns 200; `== External services ==` is present
      if the plugin makes any remote call.
- [ ] The ZIP contains no `.claude/`, `CLAUDE.md`, `.cursor/`, `.github/`, tests, tooling,
      dotfiles or archives.
- [ ] Not resubmitting from another account, and not asking for a status update before a
      month has passed — both slow the queue or get the submission rejected.

## Tone

Reviewers are volunteers working a queue of hundreds of plugins a week. Do not argue
guideline interpretation in the first reply — fix it, or state the technical constraint in
two sentences and the alternative you chose. A reply that can be read in twenty seconds is
the one that gets processed.
