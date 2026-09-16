# wp-plugin-submit-checker

A pre-submission gate for the WordPress.org plugin directory. It answers one question —
*will this plugin be approved?* — and refuses to guess at the answer.

Five gates run in order, each with a hard pass/fail: the plugin **name and slug** (first,
because the slug is immutable after approval), **Plugin Check** run the way wordpress.org
runs it at upload, the **human-reviewer rules** no static check covers, the **shipped
payload**, and the **submission or reply packet**.

What makes it different from running `wp plugin check` yourself:

- It knows what Plugin Check **does not** check. There is no nonce check (the class exists
  but is never registered). The `accessibility` category is empty. Trademark findings are
  warnings and never block the upload. External-service disclosure, bundled-library
  currency and contributor↔owner mapping have no check at all. Each of these is a common
  rejection reason, and each is swept by hand at Gate 2.
- It runs the checker the way the directory does — the **built ZIP** under its real slug
  directory, `--mode=new`, no exclude flags — and it **proves the run was real** rather
  than assuming: `--self-test` injects a known-bad file and asserts it is flagged, because
  a checker that failed to load looks exactly like a clean plugin.
- It gets the **runtime checks actually running**, which takes two independent and
  entirely undocumented conditions: `--require=cli.php` placed *after* `plugin check`, and
  the plugin *activated*. Miss either and five checks vanish with no message. On a test
  fixture that difference was 1 finding versus 10.
- Its facts are **generated from Plugin Check source**, not written from memory.
  `references/plugin-check-catalog.md` and `scripts/trademark-slugs.txt` are produced by
  `scripts/refresh-catalog.mjs` and stamped with the version they came from.

```sh
scripts/name-check.sh "My Plugin" my-plugin          # Gate 0
scripts/pcp-gate.sh dist/my-plugin.zip --mode=new --self-test   # Gate 1
node scripts/refresh-catalog.mjs --download          # refresh after a Plugin Check release
```

`pcp-gate.sh` needs Docker. It reuses a local `wordpress:cli*` image if there is one; set
`PCPGATE_CLI_IMAGE` to choose. `PLUGIN_CHECK_ZIP=/path/to/plugin-check.zip` installs the
checker offline.

## Install

Clone into your agent's skills directory — the repository root *is* the skill:

```sh
git clone https://github.com/iOSDevSK/wp-plugin-submit-checker.git \
  ~/.claude/skills/wp-plugin-submit-checker
```

Then ask for it by name, or say something like "check this plugin before I submit it to
wordpress.org".

Requirements: **Docker** (for `pcp-gate.sh` — it boots a throwaway WordPress), `node`,
`python3`, `curl`. Nothing is installed into your own WordPress.

## Layout

```
SKILL.md                                 the five gates
references/plugin-check-catalog.md       GENERATED — every check, code and severity
references/naming-and-trademarks.md      Gate 0: the glossary and the slug semantics
references/reviewer-findings.md          Gate 2: 18 findings, each with a detect command
references/justifying-false-positives.md what the reviewer accepts as a false positive
references/readme-and-headers.md         readme.txt and plugin header rules
references/distribution-payload.md       Gate 3: the ZIP, write locations, SVN
references/runtime-checks.md             why the 5 runtime checks silently do not run
scripts/refresh-catalog.mjs              regenerates the catalog from Plugin Check source
scripts/pcp-gate.sh                      Gate 1 runner
scripts/name-check.sh                    Gate 0 runner
scripts/trademark-slugs.txt              GENERATED — Trademarks_Check data, order preserved
templates/review-reply.md                reply to a review email
templates/distignore                     starting .distignore
```

## Credits

The Gate 2 findings catalog is adapted from the `wp-org-review` skill in
[soderlind/skills](https://github.com/soderlind/skills) (MIT — GPL-compatible). Everything
else is derived from the [WordPress Plugin Check](https://wordpress.org/plugins/plugin-check/)
source (GPLv2-or-later) — including its `prompts/` directory, which carries the Plugins
Team's own naming and code-review prompts.

This project is not affiliated with or endorsed by the WordPress Foundation or the
WordPress.org Plugins Team. It is a reading of their published tooling, and it does not
decide anything — only a reviewer does.

## Licence

GNU General Public License v2.0 — see [LICENSE](LICENSE).
