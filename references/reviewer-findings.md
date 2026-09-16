# Gate 2 — what the human reviewer catches that no sniff does

**Local silence is not approval.** The reviewer re-scans the whole tree **without
honouring your `phpcs:ignore` comments**, checks rules no static analyser evaluates
(contributor↔owner mapping, write locations, trademarks, external-service disclosure), and
expects **every** occurrence fixed — not only the lines they quoted.

Each finding below carries a detection command and the Plugin Check code that *partially*
covers it, so you can see where the tool stops and the human starts.

Placeholders: `myplugin` = display name, `my-plugin` = slug, `mypfx` = your prefix (≥4 chars).

*Adapted from the `wp-org-review` skill in [soderlind/skills](https://github.com/soderlind/skills) (MIT), extended against Plugin Check 2.1.0 source and the Plugins Team's own review prompts.*

---

## 1. Prefixing — every global symbol

> Partially covered by `prefixing` — **which reports only ever as a WARNING**, so it never
> blocks the upload form. The reviewer still raises it.

Everything you define in the public namespace needs a prefix unique to the plugin:
functions, classes, namespaces, constants, options, transients, meta keys, hooks,
shortcodes, globals, cron events, script/style handles, localized JS object names.

- **≥ 4 characters.** Two- and three-letter prefixes are rejected.
- Not `wp_`, `_`, `__` (reserved for core).
- Not a common word — `ai`, `seo`, `wc`, `woo` count as effectively unprefixed.
- **Do not** wrap definitions in `if ( ! function_exists() )` / `class_exists()` to dodge
  conflicts: if another plugin defines the name first and loads first, yours silently
  breaks. Reserve those guards for genuinely shared libraries.
- A PSR-4 namespace counts **only** if the root segment is distinctive. Bare
  `namespace Settings;` fails.
- **Core hook names must not be prefixed.** `the_content`, `nonce_life` etc. will trip
  `PrefixAllGlobals.NonPrefixedHooknameFound` — that is a warning you accept and record.

```sh
grep -rnE --include='*.php' --exclude-dir={vendor,node_modules,.git,tests,dist,build} \
  "function [a-z0-9_]+\(|^\s*(class|trait|interface) |namespace |define\(|const [A-Z]" .
grep -rnE --include='*.php' --exclude-dir={vendor,node_modules,.git,tests,dist,build} \
  "update_option\(|get_option\(|add_option\(|set_transient\(|get_transient\(" .
grep -rnE --include='*.php' --exclude-dir={vendor,node_modules,.git,tests,dist,build} \
  "wp_enqueue_(script|style)\(|wp_register_(script|style)\(|wp_localize_script\(" .
grep -rnE --include='*.php' --exclude-dir={vendor,node_modules,.git,tests,dist,build} \
  "add_shortcode\(|register_setting\(|wp_schedule_event\(|add_action\( *'wp_ajax_" .
```

Provide a migration for renamed option keys so existing installs keep their data.

## 2. File / directory / URL locations

> Not covered by any check.

See `distribution-payload.md` → "Locating your own files". Anchor to `__FILE__`; never
`WP_PLUGIN_DIR`, `WP_CONTENT_DIR`, `ABSPATH` or a hard-coded path.

```sh
grep -rnE --include='*.php' --exclude-dir={vendor,node_modules,.git,tests,dist,build} \
  "WP_PLUGIN_DIR|WP_CONTENT_DIR|WP_CONTENT_URL|ABSPATH" .
```

## 3. Where the plugin writes

> Partially covered by `write_file`.

See `distribution-payload.md` → "Where a plugin may write". Database, media library, or
`uploads/<slug>/` resolved at runtime. Never the plugin's own folder, core, another
plugin/theme, or an arbitrary user path.

## 4. Unneeded files in the package

> Covered by `file_type`, `plugin_content` — see `distribution-payload.md`.

## 5. Out-of-date bundled libraries

> **No check covers this.**

Every bundled third-party library must be on its latest **stable** release (no betas/RCs).
Bump, rebuild `vendor/`, and re-verify the version that actually ships in the ZIP — not
the one in `composer.json`.

## 6. Update checkers / calling home for updates

> Covered by `plugin_updater`.

Directory-hosted plugins must not bundle self-update code or ask an external server about
updates. Updates come from wordpress.org; interfering with the built-in updater is
prohibited.

```sh
grep -rniE "plugin-?update-?checker|PucFactory|pre_set_site_transient_update_plugins|site_transient_update_plugins|plugins_api|puc_" .
grep -rn "Update URI" .
```

Remove the library and any off-wordpress.org `Update URI:` header. Keep such code only in
a separate, non-directory build.

## 7. `register_setting()` sanitization

> Covered by `setting_sanitization`. See `justifying-false-positives.md` for what counts.

```php
register_setting( 'mypfx_group', 'mypfx_option', array(
    'type'              => 'string',
    'sanitize_callback' => 'sanitize_text_field', // a dedicated callback for arrays
) );
```

## 8. `load_plugin_textdomain()`

> Surfaces as `DiscouragedFunctions.load_plugin_textdomainFound`.

Unnecessary since WP 4.6 for directory-hosted plugins — **delete the call**. If kept for
pre-4.6 support, hook it on `init`, never earlier (or you get the "loaded too early"
notice).

```sh
grep -rn "load_plugin_textdomain" .
```

## 9. `Contributors` ↔ slug owner

> Partially covered by `readme_invalid_contributors` — but the check cannot know **which**
> account owns your slug.

See `readme-and-headers.md` → Contributors. It is the wordpress.org username, not your
GitHub handle, and `profiles.wordpress.org` rendering a page proves nothing.

## 10. Enqueue scripts and styles — no raw tags

> Partially covered by `enqueued_resources` and the escaping sniffs.

Files via `wp_register_script()`/`wp_enqueue_script()` (and the style equivalents); inline
via `wp_add_inline_script()`/`wp_add_inline_style()` attached to a registered handle; admin
pages via `admin_enqueue_scripts`. `async`/`defer` are supported natively since WP 6.3/5.7.

```sh
grep -rnE --include='*.php' --exclude-dir={vendor,node_modules,.git,tests,dist,build} "<script|<style" .
```

A genuinely inert placeholder node (`type="text/plain"`, read later via `.textContent`) is
the one exception — keep it, escape the body, and justify the ignore.

## 11. Output escaping

> Covered by `late_escaping`. See `justifying-false-positives.md`.

| Context | Function |
|---|---|
| URLs | `esc_url()` |
| HTML attributes | `esc_attr()` |
| Text in HTML | `esc_html()` |
| Rich HTML | `wp_kses()` / `wp_kses_post()` |

Escape the variable, not the literal, at the point of output, with the most restrictive
function that fits.

## 12. Input sanitization, nonces, capabilities

> `ValidatedSanitizedInput` and `NonceVerification` reach you **only** through
> `plugin_review_phpcs` — and **there is no dedicated nonce check at all**. The submission
> page names unescaped output, unsanitized input, and form data processed without a nonce
> as three of the four most common rejection reasons. **Sweep these by hand.**

- Every `admin_post_*` / `wp_ajax_*` handler: nonce **and** `current_user_can()`.
- Every `register_rest_route()`: a real `permission_callback`. `__return_true` is
  acceptable only on a genuinely public read-only endpoint — and write down why.
- Every redirect to a user-supplied URL: validate the destination against a stored
  allowlist first. `wp_safe_redirect()` cannot express an external OAuth `redirect_uri`,
  so validate explicitly and annotate.
- No bare variable reaching `echo`.

```sh
grep -rn "register_rest_route\|__return_true" --include='*.php' .
grep -rn "admin_post_\|wp_ajax_" --include='*.php' .
```

## 13. Trademarks in the name and slug

> Covered by `trademarks` — as a **warning**, which does not block the upload. The
> rejection comes from a person. See `naming-and-trademarks.md`.

## 14. External / third-party services (Guideline 6)

> **No check covers this.** Omitting it is a routine rejection.

Disclose every remote call — including to a service you operate — in `readme.txt`. See
`readme-and-headers.md` → `== External services ==`.

Never track users without explicit consent (guidelines 7 & 9); do not load remote code or
hijack the admin dashboard (guideline 11); no third-party CDN for JS or CSS (fonts
excepted, guideline 8).

## 15. Valid, public URLs

> Partially covered (`plugin_header_invalid_plugin_uri`, `…_author_uri`).

`Plugin URI`, `Author URI` and every repository/doc link in `readme.txt` must return 200.
Private repos and not-yet-pushed doc files fail. Detection command in
`readme-and-headers.md`.

## 16. Readme clarity and header accuracy

> Covered by `plugin_readme`, `plugin_header_fields`. See `readme-and-headers.md`.

## 17. Suppressed sniffs

> **No check covers this — by construction.** The reviewer re-scans without your ignores.

```sh
grep -rn --include='*.php' --exclude-dir={vendor,node_modules,.git,tests,dist,build} \
  "phpcs:ignore\|phpcs:disable" .
```

Every hit is either a real fix waiting to happen, or needs a `--` justification that
matches `justifying-false-positives.md`. A bare ignore reads as concealment.

## 18. Guideline wording problems in a compliant codebase

> **No check covers this.**

- No "best" / "#1" / "the only" / "the most" claims (guideline 9).
- **No trialware** (guideline 5): functionality may not be locked behind payment or
  disabled after a trial or quota. Sandbox-only API access counts as trialware. The
  guideline explicitly recommends add-on plugins hosted outside wordpress.org for premium
  code.
- Never describe data the plugin **already stores** as something the paid edition
  "unlocks" or "reveals" — that is "implying users must pay to unlock included features".
- Human-readable code (guideline 4): **source and any build tools must be publicly
  accessible**, bundled or linked from the readme.
- "Powered by" credits default to off (guideline 10); admin notices must be contextual and
  dismissible (guideline 11).

---

## The 18 guidelines

<https://developer.wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines/>

1. GPL-compatible licence for all code, data and images (GPLv2-or-later recommended);
   third-party libraries and images must be compatible too.
2. The developer is responsible for everything in the package.
3. A stable version must be available from the directory page.
4. Human-readable code — no obfuscation, no minification without source; source **and
   build tools** publicly accessible.
5. No trialware.
6. SaaS is allowed; licence-validation-only services and artificially separated
   functionality are not.
7. No user tracking without explicit opt-in.
8. No executable code from third-party servers; no updates from anywhere but
   wordpress.org; no third-party CDN for JS/CSS (fonts excepted); no iframing admin pages.
9. No illegal, dishonest or offensive conduct — including keyword stuffing and implying
   users must pay to unlock included features.
10. No unauthorised external links; "powered by" credits default to off.
11. No admin-dashboard hijacking; notices contextual and dismissible.
12. No spam in the readme; **max 5 tags**; no competitor tags.
13. Use WordPress's bundled libraries (jQuery, PHPMailer, SimplePie, …).
14. SVN is a release repository, not a development one.
15. Increment the version, or nobody is offered the update.
16. Submit a complete plugin; slugs cannot be reserved.
17. Respect trademarks. A slug may not begin with a trademarked term.
18. The directory reserves the right to change rules and disable plugins.

## The submission itself

- URL: **`https://wordpress.org/plugins/developers/add/`** (plural).
- **2FA on the submitting wordpress.org account is mandatory.**
- Since **October 2024** the upload is run through Plugin Check's `plugin_repo` category
  first: **any ERROR blocks the form** and no human ever sees the plugin. Warnings do not
  block.
- Human review follows: 1–10 days, 5 business days targeted.
- **The account email is the plugin's ownership proof.** Free-email providers are refused
  for ownership, it must be a real mailbox — not a forwarder, not an email-routing rule —
  and a bounce on it can get a published plugin closed.
