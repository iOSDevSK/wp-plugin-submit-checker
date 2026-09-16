# readme.txt and the plugin header

Spec: <https://developer.wordpress.org/plugins/wordpress-org/how-your-readme-txt-works/>
(append `?output_format=md` to any wordpress.org page for a clean render).

```
=== Plugin Name ===
Contributors: wporg-username
Tags: up, to, five, tags, max
Requires at least: 6.6
Tested up to: 7.0
Requires PHP: 7.4
Stable tag: 1.19.6
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

One line, 150 characters maximum, plain text.

== Description ==
```

## The agreements that must hold

| Must equal | | Enforced by |
|---|---|---|
| `=== Name ===` | header `Plugin Name` | `mismatched_plugin_name` |
| `Stable tag` | header `Version` | `stable_tag_mismatch` |
| `Text Domain` | the slug | `textdomain_mismatch` |
| readme `License` | header `License` | `license_mismatch` |
| readme `Tested up to` | header `Tested up to`, **if the header has one** | `mismatched_tested_up_to_header` |

**Put `Tested up to` only in `readme.txt`.** If the plugin header carries one too, they
must match — and they drift. Declare the version you actually tested against.

**`Tested up to` must be the current WordPress major** — `7.0`, not `7.0.3`
(`invalid_tested_upto_minor`). An older value means, in Plugin Check's own words, *"your
plugin will not show up in searches"*.

> **Mode matters.** In `--mode=new` an outdated `Tested up to` is an **ERROR** and blocks
> the upload; in `--mode=update` the same finding is only a warning. Check a first
> submission as `new`.

Check the current version before every submission:

```sh
curl -s https://api.wordpress.org/core/version-check/1.7/ | head -c 200
```

## `Contributors`

Case-sensitive, comma-separated **WordPress.org usernames**. It must include the account
that **owns the slug** — named in the review email as "owner of the plugin '<username>'".

- **It is not your GitHub handle.** A username that does not exist is silently dropped by
  the importer, and raises its own warning.
- **`profiles.wordpress.org` renders a page for arbitrary slugs**, so loading that URL is
  *not* a valid way to prove an account exists. Log in and check, or use an account you
  have actually authenticated with.
- Reserved names (`wordpressdotorg`, `automattic`, …) are refused outright
  (`readme_reserved_contributors`, `readme_restricted_contributors`).

## Tags

Maximum 5. Generic terms on a blocklist are silently dropped. No competitor names, no
keyword stuffing (guideline 12). Spend them on phrases the plugin can realistically own —
a tag owned by a 10M-install plugin buys nothing.

## Sections reviewers expect beyond the standard set

### `== External services ==` — required for any remote call

Omitting it is a routine rejection, and it applies **even to a service you operate
yourself**.

```text
== External services ==

This plugin connects to <Service> to <purpose>.
It sends <what data> to <endpoint> when <trigger/condition>.
This service is provided by <Provider>: <terms of service URL>, <privacy policy URL>.
```

Verify both links resolve. Detect what needs disclosing:

```sh
grep -rnE --include='*.php' --exclude-dir={vendor,node_modules,.git,tests,dist,build} \
  "wp_remote_(get|post|request)|curl_|file_get_contents\( *'https?://" .
```

### `== Privacy ==`
What is stored, and what is not.

### `== Screenshots ==`
Only once the images exist. They live in the **SVN `assets/` directory**
(`screenshot-1.png`, …) and **never** in the plugin ZIP.

### `== Upgrade Notice ==`
Each entry is length-limited (`upgrade_notice_limit`). Keep it short.

## Header fields

- `Plugin URI` / `Author URI` must resolve (200, not 404) and must not be on a
  "discouraged domain" — github.com among them, which yields a warning, not an error.
- The plugin name needs at least 5 latin characters.
- `Requires Plugins` — since Plugin Check 2.1.0 **each dependency is validated
  individually against the wordpress.org directory**. A dependency that is not a
  directory-hosted slug fails (`plugin_header_requires_plugins_not_in_directory`).
- `Requires at least` is cross-checked against the WordPress functions you actually call
  (`wp_functions_compatibility` → `wp_function_not_compatible_with_requires_wp`): calling a
  function newer than your declared floor is a finding.
- Restricted header fields exist (`plugin_header_restricted_fields`) — notably
  `Update URI` pointing off wordpress.org, which is also `plugin_updater`.
- `load_plugin_textdomain()` is unnecessary for a directory-hosted plugin since WP 4.6 —
  WordPress loads translations by slug. **Delete the call**; keep `Domain Path` and ship
  the `.pot`. If you keep it for pre-4.6 support it must run on `init`, not earlier.

Check every URL you publish:

```sh
grep -rnhoE --include='*.php' --include='readme.txt' \
  --exclude-dir={vendor,node_modules,.git,tests,dist,build} "https?://[^ )\"'<>]+" . \
  | sort -u | while read -r u; do
      printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' -L "$u")" "$u"
    done
```

## Content rules that live in the readme

- No claim to be the best / the only / #1 / the most — treated as dishonest (guideline 9).
- No keyword stuffing.
- No implying users must pay to unlock features that already ship. This is where a
  *compliant codebase* still fails on *wording*: never describe data the plugin already
  stores as something the paid edition "unlocks" or "reveals".
- Install instructions must name the **current** slug. A stale
  `/wp-content/plugins/old-slug` path is flagged as unclear.
- Default/placeholder text anywhere fails (`default_readme_text`).
- The description must let someone set the plugin up from scratch.

## The codes these rules produce

<!-- GENERATED:start:header-codes -->
Generated by `scripts/refresh-catalog.mjs` from **Plugin Check 2.1.0**. Do not edit by hand.

**`plugin_header_fields` errors:** `plugin_header_invalid_author_uri`, `plugin_header_invalid_author_uri_domain`, `plugin_header_invalid_license`, `plugin_header_invalid_network`, `plugin_header_invalid_plugin_description`, `plugin_header_invalid_plugin_name`, `plugin_header_invalid_plugin_uri`, `plugin_header_invalid_plugin_uri_domain`, `plugin_header_invalid_plugin_version`, `plugin_header_invalid_requires_php`, `plugin_header_invalid_requires_plugins`, `plugin_header_invalid_requires_wp`, `plugin_header_missing_plugin_description`, `plugin_header_missing_plugin_version`, `plugin_header_no_license`, `plugin_header_nonexistent_requires_wp`, `plugin_header_restricted_fields`, `plugin_header_unsupported_plugin_name`, `textdomain_invalid_format`

**`plugin_header_fields` warnings:** `plugin_header_invalid_domain_path`, `plugin_header_nonexistent_domain_path`, `plugin_header_requires_plugins_not_in_directory`, `textdomain_mismatch`

**`plugin_readme` errors:** `default_readme_text`, `empty_plugin_name`, `invalid_license`, `invalid_plugin_name`, `invalid_tested_upto_minor`, `license_mismatch`, `mismatched_tested_up_to_header`, `missing_readme_header_*`, `no_license`, `no_plugin_readme`, `no_stable_tag`, `nonexistent_tested_upto_header`, `outdated_tested_upto_header`, `readme_description_non_official_language`, `readme_invalid_donate_link`, `readme_invalid_donate_link_domain`, `readme_mismatched_header_*`, `readme_restricted_contributors`, `readme_short_description_non_official_language`, `stable_tag_mismatch`, `trunk_stable_tag`

**`plugin_readme` warnings:** `mismatched_plugin_name`, `outdated_tested_upto_header`, `readme_invalid_contributors`, `readme_parser_warnings_*`, `readme_reserved_contributors`, `upgrade_notice_limit`
<!-- GENERATED:end:header-codes -->

Quick local audit:

```sh
grep -nE "^(Stable tag|Requires at least|Requires PHP|Tested up to|License|License URI|Contributors|Tags):" readme.txt
grep -n "wp-content/plugins/" readme.txt        # the slug must match
grep -rn "load_plugin_textdomain" .
```
