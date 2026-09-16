# Writing a `phpcs:ignore` the reviewer will accept

**Distilled from Plugin Check's own `prompts/ai-review-*.md`** — the prompts the
WordPress.org tooling uses when it re-reads a flagged line to decide whether the finding is
genuine. They are the closest thing that exists to a written specification of what counts
as a legitimate exception.

Two rules frame everything below:

1. **A bare `phpcs:ignore` reads as hiding a problem.** The reviewer re-scans the tree
   *without honouring your ignore comments*, so every suppressed line is re-flagged and
   then read by a human. An ignore with a `--` justification reads as "reviewed"; one
   without reads as "concealed".
2. **Fix it if it is real.** These notes exist to tell the two apart, not to supply
   excuses. If the code below describes your situation, annotate. If it does not, fix.

Format — the reason goes after `--`, on **the line the sniff actually fires on**:

```php
// phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared -- table name is interpolated from $wpdb->prefix; all values are placeholders below.
```

Placement matters and is a common own-goal: put the annotation on the line holding the SQL
string, not on the outer `$wpdb->get_row(` line, or it does not apply at all.

---

## Escaping — `late_escaping` / `WordPress.Security.EscapeOutput`

**Accepted as a non-issue**

- The value is a hardcoded string with no variables.
- The value is the direct return of an escaping function.
- The value comes from a function that escapes internally — `get_avatar()`,
  `paginate_links()`, `wp_nonce_field()` — *depending on context*.
- The data demonstrably flows through an escaping function before the output point.

**Never accepted**

- Escaping early and outputting later. "Late" means *at the output statement*.
- `__()`, `_e()`, `_x()` — i18n functions **do not escape**.
- `printf()` / `sprintf()` — they do not escape either.

**Context traps**

- Inside `<style>`, `esc_html()` is **wrong**: entities are not decoded there, so a `>`
  child selector becomes a literal `&gt;` and the CSS breaks. `wp_strip_all_tags()` plus a
  justification is the correct shape.
- For an inert `type="text/plain"` script node read back via `.textContent`, `esc_html()`
  *is* right: it blocks a `</script>` breakout and the consumer decodes entities anyway.
  Confirm the consumer uses `.textContent` and not `.innerHTML` before relying on it.

## Sanitization — `WordPress.Security.ValidatedSanitizedInput`

**Accepted**

- Type casting — `(int)`, `(float)`, `(bool)` — for the matching type.
- Data passed straight to a function that sanitizes it itself (e.g. `update_option()` on
  an option with a registered sanitize callback).
- Data used only in a comparison (`if ( $_GET['action'] === 'delete' )`) — lower risk,
  though sanitizing anyway is recommended.

**Never accepted**

- `isset()` / `empty()` as sanitization. They are not.
- `wp_unslash()` alone. It is not a sanitizer.
- Unsanitized array access on a superglobal — the elements need it too.

Superglobals in scope: `$_POST`, `$_GET`, `$_REQUEST`, `$_SERVER`, `$_COOKIE`.

## Nonces — `WordPress.Security.NonceVerification`

> **There is no dedicated nonce check.** `Nonce_Verification_Check` exists in the Plugin
> Check source but is never registered, so it never runs. Nonce problems reach you only
> through `plugin_review_phpcs`, which a `phpcs:ignore` silences — and "form data processed
> without a nonce" is one of the four reasons the submission page names for rejection.
> **Sweep this by hand.** A clean Plugin Check run is not evidence here.

**Accepted**

- The nonce check happens earlier in the same function, or in the calling function.
- A REST API callback with a real `permission_callback` — REST uses a different
  authentication mechanism and does not need a nonce.
- Reading `$_GET`/`$_POST` purely for display, not for processing or saving — in some
  contexts.

**Never accepted**

- `current_user_can()` on its own. A capability check is not a nonce; form submissions
  need both.
- An AJAX handler with no `check_ajax_referer()` / `wp_verify_nonce()`.

Verification functions: `wp_verify_nonce()`, `check_admin_referer()`, `check_ajax_referer()`.

## Direct DB queries — `direct_db`, `direct_db_queries`

**Accepted**

- Queries built only from hardcoded values need no `prepare()`.
- `$wpdb->insert()`, `update()`, `delete()`, `replace()` prepare themselves **when format
  parameters are supplied**.
- **Table names cannot be prepared** — `$wpdb->prefix` concatenation is the accepted shape.
- Column names cannot be prepared either — whitelist/validate them instead.
- Variables from a trusted source (`$wpdb->posts`, `$wpdb->prefix`).

**Needs care**

- `IN (…)` with a dynamic list needs one placeholder per element (`array_fill`) — which
  then trips `PreparedSQLPlaceholders.UnfinishedPrepare`, and *that* is the annotatable
  finding.
- PHPCS cannot see through an interpolated table name even when every value is a
  placeholder. Prefer one literal query — use `( %s = '' OR col = %s )` for optional
  filters — so the placeholders are visible in the string literal. Building a WHERE clause
  by concatenation hides them from analysis and trips `UnescapedDBParameter` on code that
  is in fact safe.
- `DirectDatabaseQuery.DirectQuery` / `.NoCaching` on a plugin's own custom tables are
  routinely accepted warnings — cache where you sensibly can, then annotate.

## `register_setting()` — `setting_sanitization`

**Accepted**

- A third argument containing `sanitize_callback`.
- A `sanitize_option_{$option}` filter doing the work.
- Simple booleans/integers with appropriate type casting — *may* be acceptable.

`type` + `show_in_rest` with a schema gets you *some* validation, but explicit
sanitization is still expected. For array or object options write a dedicated callback
that sanitizes each field; scalar sanitizers are not enough.

## Code obfuscation — `code_obfuscation`

**Not obfuscation**

- Minified JS/CSS — that is `minified_files`, a different finding.
- Base64 for images, fonts or other non-executable content.
- Encoded strings used as configuration, tokens or data payloads that are never executed.
- `base64_decode()` on data rather than code — generally fine. (Binary-safe transport of
  ciphertext is a legitimate annotation.)

**Is obfuscation**

- base64-encoded PHP that is decoded and executed; `eval`'d strings; encoded variable
  names; packed JavaScript (Dean Edwards packer and friends).
- `str_rot13()` applied to executable code.
- **`eval()` is flagged always, in every context.**

## Plugin updaters — `plugin_updater`

**Accepted**

- Modifying the auto-update UI (enabling/disabling core auto-updates).
- Licence-key validation that gates *features* — a separate concern from updates.
- Code inside an excluded directory such as `vendor/` may not be flagged (but shipping it
  is still a risk at human review).

**Never accepted**

- Hooking `pre_set_site_transient_update_plugins` / `site_transient_update_plugins` /
  `plugins_api`.
- Bundling `plugin-update-checker`, `PucFactory` or any custom class that asks an external
  server about updates.
- An `Update URI:` header pointing anywhere but wordpress.org.

Keep such code only in a separate, non-directory build.

## Anything else — the generic prompt

The reviewer is told to: read the broader context rather than the single flagged line;
check whether the issue is mitigated elsewhere in the same function or file; accept
commonly-used, generally-accepted WordPress patterns; and consider whether the flagged
issue even applies in that context (admin-only code, CLI context, and so on).

Write your justification to answer exactly that question — *why the surrounding context
makes this line safe* — in one sentence, in plain language.

---

## Warnings you may knowingly accept

Not everything must reach zero. The gate is **zero errors**; warnings are either fixed or
**written down with a reason**. Ones that recur legitimately:

- `DirectDatabaseQuery.DirectQuery` / `.NoCaching` on the plugin's own custom tables.
- `PluginCheck.Security.DirectDB.UnescapedDBParameter` on interpolated table names.
- `PrefixAllGlobals.NonPrefixedHooknameFound` for **core** hook names (`the_content`,
  `nonce_life`) — those are correctly named and must not be prefixed.
- `WPQueryParams.PostNotIn_post__not_in` where the exclusion is genuinely required.
- `AlternativeFunctions.file_system_operations_*` when streaming to `php://output`, where
  `WP_Filesystem` has no equivalent.

An accepted warning that is not recorded in the report is a bug in the report.
