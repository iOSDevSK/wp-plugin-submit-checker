---
name: wp-plugin-submit-checker
description: >
  Drive a WordPress plugin to APPROVAL in the official WordPress.org plugin directory.
  Runs the same automated gate wordpress.org runs at upload, plus the human-reviewer rules
  no static check covers: plugin name and slug against the Plugins Team's own trademark
  glossary, readme and header agreement, external-service disclosure, write locations, the
  shipped payload, and nonce/escaping/sanitization sweeps. Use when the user asks to
  "zverejnit plugin na wordpress.org", "pripravit plugin na wp.org", "skontroluj plugin
  pred submitom", "preco mi zamietli plugin", "odpovedz na review email", "submit my plugin
  to the directory", "plugin check", "will wordpress approve this", or is responding to a
  Plugin Directory review email. Covers first submissions and resubmissions after a
  rejection. It stops at "ready to submit" — the SVN release itself belongs to the
  per-plugin release skill.
---

# Get a plugin approved by the WordPress.org directory

Five gates, in order. **Do not advance past a failing gate**, and always say which gate you
stopped at. Report what you skipped and why.

The ordering is not cosmetic. **Gate 0 is first because the slug is immutable after
approval** — a name problem found later cannot be fixed, only resubmitted as a new plugin
with zero installs.

| Gate | Question | Hard condition |
|---|---|---|
| **0 Name & slug** | Will the name be rejected? | No banned/discouraged term; trademarks only behind `for`/`with` at the end; slug clears `Trademarks_Check`; no confusable collision |
| **1 Plugin Check** | Will the upload form accept it? | **Zero errors.** Every remaining warning fixed *or* written down with a justification |
| **2 Human rules** | Will the reviewer reject it? | Every row in `reviewer-findings.md` satisfied or justified |
| **3 Payload** | Is the ZIP what should ship? | No `file_type`/`plugin_content` findings; no dev artefacts |
| **4 Packet** | Ready to send? | Headers ↔ readme agree; reply drafted if resubmitting |

## Two facts that reshape how you work

**A clean Plugin Check run is not approval.** It is one of two independent systems. The
reviewer re-scans the whole tree **without honouring your `phpcs:ignore` comments**, and
checks rules no sniff evaluates. And crucially:

**Some of the most common rejection reasons are not checked at all.**

- `Nonce_Verification_Check` exists in the Plugin Check source but is **never registered**
  — it never runs. Nonce problems reach you only via `plugin_review_phpcs`, which an ignore
  comment silences. "Form data processed without a nonce" is one of the four reasons the
  submission page names for rejection. **Sweep by hand at Gate 2.**
- `trademarks` reports `trademarked_term` as a **WARNING**, and warnings do not block the
  upload. The name rejection arrives later, from a person. **That is why Gate 0 is separate
  and first.**
- The `accessibility` category is defined but **no check uses it** — `--categories=accessibility`
  runs nothing.
- External-service disclosure, bundled-library currency, trialware wording, and
  contributor↔owner mapping have **no check at all**.

---

## Gate 0 — Name & slug

```sh
scripts/name-check.sh "<display name>" [<slug>]
```

It ports `Trademarks_Check::has_trademarked_slug()` faithfully from the Plugin Check
source (including that the real check **breaks on the first match**, and that the
`-for-<term>` escape hatch applies to **exactly one** trademark), then queries the
directory for a taken slug and confusable names.

Read **`references/naming-and-trademarks.md`** for the full glossary and the judgement
calls the script cannot make: genericness, keyword stuffing, and whether a
trademark-looking coined word is actually the author's.

On failure, output the shape of the real rejection email — the problem, then a compliant
suggested display name **and slug**.

## Gate 1 — Plugin Check, the way wordpress.org runs it

```sh
scripts/pcp-gate.sh <plugin.zip|plugin-dir> --mode=new --self-test --json=findings.json
```

Boots a throwaway WordPress in Docker, installs the payload as
`wp-content/plugins/<slug>/`, installs Plugin Check, and runs it with the flags that
matter. Every one of them exists because omitting it produced a false pass:

- **The built ZIP, extracted under its real slug name** — not the working tree. A
  differently-named directory floods the run with bogus `textdomain_mismatch`.
- **`--mode=new`** for a first submission. In `new` mode an outdated `Tested up to` is an
  **error**; in `update` the same finding is only a warning.
- **`--require=<plugin-check>/cli.php`, placed AFTER `plugin check`** — *and the plugin
  must be ACTIVE*. Two independent conditions, either of which silently disables the five
  runtime checks. See `references/plugin-check-catalog.md` → "Runtime checks". `pcp-gate.sh`
  activates the plugin and then **probes** whether the runtime checks resolve, rather than
  assuming.
- **`--include-low-severity-errors --include-low-severity-warnings`, no exclude flags.**
  wordpress.org does not honour your exclusions.
- **`--self-test`** — injects unescaped output and asserts it is flagged. *A checker that
  failed to load looks exactly like a clean plugin.*

Network is required: the readme check fetches the current WordPress version,
`plugin_header_fields` validates each `Requires Plugins` entry against the directory.
Offline they degrade quietly.

**The rule, stated once:** zero errors is the hard gate. Every remaining warning is either
fixed or enumerated in the report with a justification matching
`references/justifying-false-positives.md`. An accepted warning that is not written down
is a bug in the report.

Triage each finding with **`references/plugin-check-catalog.md`** (every registered check,
its codes, its severity behaviour) and **`references/justifying-false-positives.md`** (what
the reviewer's own AI accepts as a genuine false positive, per check family).

## Gate 2 — What the reviewer catches and no sniff does

Work through **`references/reviewer-findings.md`** — 18 findings, each with a detection
command and the code that *partially* covers it, so you can see where the tool stops.

Start here, because these are re-flagged regardless of what your tooling said:

```sh
# Every suppressed sniff is an UNREVIEWED line. The reviewer re-scans without them.
grep -rn --include='*.php' --exclude-dir={vendor,node_modules,.git,tests,dist,build} \
  "phpcs:ignore\|phpcs:disable" .
```

Each hit is either a real fix, or needs a `--` justification. A bare ignore reads as
concealment.

Then the hand sweeps, in the order the submission page ranks them: unescaped output,
unsanitized input, **nonces** (no check covers these), guideline compliance.

## Gate 3 — The payload

Build the real ZIP and inspect **the ZIP**. See **`references/distribution-payload.md`**.

The traps that catch working repos: `ai_instruction_directory` (`.claude/`, `CLAUDE.md`,
`.cursor/`, `AGENTS.md`), `hidden_files` (any dotfile), `compressed_files` (the build
output left in the tree), `missing_composer_json_file` (`vendor/` without its manifest).
A `.distignore` template is in `templates/distignore`.

If the build script keeps its own hard-coded copy list, `.distignore` alone is not enough —
**both** must be updated.

## Gate 4 — Submission or reply packet

Final agreement check per **`references/readme-and-headers.md`**: `=== Name ===` ↔ header
`Plugin Name`; `Stable tag` ↔ header `Version`; `Text Domain` ↔ slug; `Tested up to` in
**readme only**, at the current WordPress major; ≤5 tags; ≤150-char short description.

- Submit at **`https://wordpress.org/plugins/developers/add/`** (plural). **2FA is mandatory.**
- The wordpress.org account email is the plugin's ownership proof. Free-email providers are
  refused for ownership; it must be a real mailbox, not a forwarder or routing rule. **A
  bounce on it can get a published plugin closed.**
- **Resubmitting after a review email?** Use `templates/review-reply.md`: each quoted
  finding → code → what changed → where, and an explicit desired-slug line. Renaming the
  display name alone does not change the slug.
- **Already published?** Check SVN `trunk`/`tags`/`assets` for unexpected files, and
  confirm `Stable tag` names a tag that actually exists — if it does not, the directory
  silently serves trunk.

---

## Keeping this skill honest

Everything in `references/plugin-check-catalog.md` and `scripts/trademark-slugs.txt` is
**generated from Plugin Check source**, never written from memory:

```sh
node scripts/refresh-catalog.mjs /path/to/plugin-check     # or --download
```

Re-run it whenever Plugin Check releases. The generated blocks are stamped with the version
they came from, so a stale catalog is visible. If the stamped version is older than the
Plugin Check in the container, say so rather than quoting the catalog as current.

## Reporting

Always report:

1. The gate reached, and the hard condition that failed.
2. Errors grouped by code, with file:line.
3. Warnings **accepted**, each with its written justification.
4. Warnings **outstanding**.
5. What was skipped and why (offline, no Docker, runtime checks not run).

Never report a gate as passed on a run you did not actually make.
