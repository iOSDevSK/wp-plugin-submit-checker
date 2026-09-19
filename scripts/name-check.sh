#!/usr/bin/env bash
# name-check.sh — Gate 0. Test a plugin display name and slug against what the code
# enforces and what the reviewer applies, then look for confusable names in the directory.
#
#   name-check.sh "<display name>" [<slug>]
#
# Exits 1 if anything blocking was found. A clean exit is NOT approval: the similar-name
# and genericness judgements are yours to make from the output.
#
# Remember the asymmetry: Trademarks_Check emits `trademarked_term` as a WARNING, so a
# trademark problem does NOT block the upload form. It comes back as a rejection email.
set -uo pipefail

NAME="${1:-}"; SLUG="${2:-}"
[ -n "$NAME" ] || { echo "usage: name-check.sh \"<display name>\" [<slug>]" >&2; exit 2; }
if [ -z "$SLUG" ]; then
  SLUG="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' \
        | sed -E -e 's/[^a-z0-9]+/-/g' -e 's/^-//' -e 's/-$//')"
fi

FAIL=0
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

LNAME="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"

# Match trademark terms on WORD BOUNDARIES, never as bare substrings. Unbounded matching
# false-blocks ordinary names — "Instant Contact Form" reads as Instagram, "Plumbing" as
# Bing, "Cloud Drive" as Rive, "Wedding" as EDD, "Popups"/"Groups" as UPS. Gate 0 is the
# hard stop, so a false block here is this skill's worst failure mode.
# Normalise to space-separated words (keeping "." so "booking.com" survives) and pad, so
# " term " can be tested. Multi-word entries work unchanged.
norm() {
  printf ' %s ' "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9.\n' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//')"
}
NNAME="$(norm "$NAME")"
NSLUG="$(norm "$SLUG")"

printf '\033[1mname:\033[0m %s\n\033[1mslug:\033[0m %s' "$NAME" "$SLUG"
[ ${#SLUG} -gt 50 ] && printf '  \033[31m(%s chars — max 50)\033[0m' "${#SLUG}"
printf '\n'
[ ${#SLUG} -gt 50 ] && FAIL=1

# ------------------------------------------------------------------- banned ---
# No placement, abbreviation or "for X" construction makes these acceptable.
step "Banned terms (no compliant placement exists)"
BANNED='facebook|fbook|fb|whatsapp|whats app|vvhatsapp|wh4tsapps|wa|instagram|insta|threads|oculus|wordpress|wpress|wordpess|trustpilot|binance pay|binance'
HIT=0
for FIELD in "$NNAME" "$NSLUG"; do
  M="$(printf '%s' "$FIELD" | grep -oiE " ($BANNED) " | tr -d ' ' | sort -u | tr '\n' ' ')"
  [ -n "$M" ] && { bad "banned term(s): $M"; HIT=1; }
done
# "WP" as a standalone word, and the "for WP" / "for WordPress" tail.
printf '%s' "$NNAME" | grep -qiE " wp " && { bad "\"WP\" as a standalone word — remove it; the directory is already WordPress"; HIT=1; }
printf '%s' "$NSLUG" | grep -qiE " wp " && { bad "slug contains \"wp\" as a segment — TRADEMARK_SLUGS matches 'wp' ANYWHERE in a slug"; HIT=1; }
[ "$HIT" = "0" ] && ok "none found"

# -------------------------------------------------------------- discouraged ---
step "Discouraged terms (remove — there is no compliant placement)"
HIT=0
printf '%s' "$NNAME" | grep -qiE " plugin " && { bad "\"Plugin\" — redundant, and forbidden as the first word"; HIT=1; }
printf '%s' "$NNAME" | grep -qiE " (best|perfect|first|the most) " && { bad "superlative — comparative claims are treated as dishonest"; HIT=1; }
printf '%s' "$NAME"  | grep -qE '#1'                                && { bad "\"#1\" — comparative claim"; HIT=1; }
printf '%s' "$NNAME" | grep -qiE " free "                           && { bad "\"Free\" — redundant in a directory of free plugins"; HIT=1; }
printf '%s' "$NNAME" | grep -qiE " (gutenberg|gberg|guten) "        && { bad "\"Gutenberg\" and fragments — the editor is called the block editor"; HIT=1; }
printf '%s' "$NNAME" | grep -qiE " [a-z0-9]*press "                 && { bad "portmanteau ending in \"-Press\" — reads as a blend on the WordPress trademark"; HIT=1; }
[ "$HIT" = "0" ] && ok "none found"

# --------------------------------------------------- other people's marks ----
step "Third-party trademarks — placement rule"
OTHER='woocommerce|woo|google analytics|google|adsense|adwords|android|chrome|gmail|youtube|apple pay|apple|macos|ios|iphone|ipad|microsoft|bing|windows|linkedin|github|skype|adobe|amazon|aws|cloudfront|booking.com|bootstrap|openai|chatgpt|chat gpt|sora|deepseek|deep seek|cloudflare|turnstile|cpanel|whmcs|disqus|dropbox|envato|fedex|firefox|font awesome|fontawesome|gtmetrix|hubspot|mailchimp|klaviyo|mailerlite|sendpulse|mailwizz|matomo|onlyfans|only fans|opera|paddle|paypal|pinterest|stripe|slack|tiktok|tik tok|twitch|twitter|bluesky|discord|telegram|ups|usps|watson|yandex|yahoo|dpd|rive|aparat|bitcoin|rutube|bkash|nagad|m.pesa|stax|sslcommerz|odoo|aliyun|alibaba|satim|sendcloud|payinn|sentry|contact form 7|cf7|advanced custom fields|acf|bbpress|buddypress|divi|dokan|easy digital downloads|edd|elementor|givewp|gravity forms|ninja forms|yoast|polylang|wpml|wpforms|pixelyoursite|beaver builder|tutor lms|buddyboss|content views|searchwp|translatepress|rank math|pods|jquery|tinymce'
FOUND="$(printf '%s' "$NNAME" | grep -oiE " ($OTHER) " | sed -e 's/^ //' -e 's/ $//' | sort -u)"
if [ -z "$FOUND" ]; then
  ok "no third-party trademark detected in the display name"
else
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    # Acceptable ONLY at the end, behind "for" or "with" — tested on word boundaries too.
    if printf '%s' "$NNAME" | grep -qiE " (for|with) ([a-z0-9.]+ )*${t} *$"; then
      ok "\"$t\" sits behind for/with at the end — acceptable placement"
    else
      bad "\"$t\" must appear ONLY at the end, after \"for\" or \"with\" (e.g. \"... for ${t}\")"
    fi
  done <<< "$FOUND"
  printf '     \033[2mIf a mark is genuinely yours (your brand/company/domain), this is fine — say so.\033[0m\n'
fi

# ------------------------------------------------------ the enforced slug ----
# A faithful port of Trademarks_Check::has_trademarked_slug(). The list is GENERATED from
# the Plugin Check source into scripts/trademark-slugs.txt by refresh-catalog.mjs, order
# preserved, because the real check BREAKS ON THE FIRST MATCH — which entry is found first
# decides the message the author gets. Hand-maintaining this list gets it wrong: stripping
# the trailing hyphens turns prefix tests into match-anywhere tests and produces false
# blocks on slugs that are in fact published (mcp-for-woocommerce among them).
step "Slug against Trademarks_Check (ported from source)"
DATA="$(dirname "$0")/trademark-slugs.txt"
if [ ! -f "$DATA" ]; then
  warn "scripts/trademark-slugs.txt missing — run: node scripts/refresh-catalog.mjs <plugin-check>"
else
  SLUGVERDICT="$(python3 - "$DATA" "$SLUG" <<'PY'
import sys
data, slug = sys.argv[1], sys.argv[2]
sec, buckets = None, {}
for line in open(data):
    line = line.rstrip("\n")
    if not line or line.startswith("#"): continue
    if line.startswith("[") and line.endswith("]"):
        sec = line[1:-1]; buckets[sec] = []; continue
    if sec: buckets[sec].append(line)
marks    = buckets.get("TRADEMARK_SLUGS", [])
excepts  = buckets.get("FOR_USE_EXCEPTIONS", [])
patterns = buckets.get("ALLOWED_PATTERNS", [])
ports    = buckets.get("PORTMANTEAUS", [])

def valid_for_use(slug, tm):
    if not slug or not tm or tm not in excepts: return False
    found = None
    for p in patterns:
        if (p + tm) in slug: found = p + tm; break
    if not found: return False
    # After removing the pattern the term must not appear anywhere else.
    return tm not in slug.replace(found, "", 1)

hit = None
for tm in marks:                       # order matters; first match wins
    if tm.endswith("-"):
        if slug.startswith(tm): hit = tm; break
    elif tm in slug:
        if valid_for_use(slug, tm): continue
        hit = tm; break
if not hit:
    for pm in ports:
        if slug.lower().startswith(pm.lower()): hit = pm; break

if not hit:
    print("OK|the slug clears the enforced list")
else:
    bare = hit.strip("-")
    if hit.endswith("-"):
        print(f"FAIL|slug BEGINS with \"{bare}\" — a prefix match. You may use it elsewhere, e.g. \"... for {bare}\"")
    elif bare in excepts:
        print(f"FAIL|slug contains \"{bare}\" — allowed only as \"for/with/using/and {bare}\", and it must not appear anywhere else in the slug")
    else:
        print(f"FAIL|slug contains \"{bare}\" — this term cannot be used at ALL in a plugin slug")
PY
)"
  VERD="${SLUGVERDICT%%|*}"; MSG="${SLUGVERDICT#*|}"
  if [ "$VERD" = "OK" ]; then ok "$MSG"; else bad "$MSG"; fi
fi

# ------------------------------------------------------------- directory -----
step "WordPress.org directory"
API="https://api.wordpress.org/plugins/info/1.2/"
TAKEN="$(curl -s --max-time 20 "${API}?action=plugin_information&request[slug]=${SLUG}" 2>/dev/null)"
if printf '%s' "$TAKEN" | grep -q '"slug"'; then
  bad "the slug \"$SLUG\" is ALREADY TAKEN — submitting would silently get you \"${SLUG}-2\""
  printf '     https://wordpress.org/plugins/%s/\n' "$SLUG"
else
  ok "slug \"$SLUG\" appears to be free"
fi

Q="$(printf '%s' "$NAME" | sed 's/ /+/g')"
RES="$(curl -s --max-time 25 "${API}?action=query_plugins&request[search]=${Q}&request[per_page]=8&request[fields][active_installs]=1" 2>/dev/null)"
if [ -n "$RES" ]; then
  printf '\n  closest existing plugins (weigh >10k installs heavily):\n'
  printf '%s' "$RES" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for p in (d.get("plugins") or [])[:8]:
    if isinstance(p,dict):
        n=p.get("name","")[:52]; s=p.get("slug",""); a=p.get("active_installs",0)
        print(f"    {a:>10,}  {n:<52}  https://wordpress.org/plugins/{s}/")
' 2>/dev/null
  printf '\n     \033[2mA name not yet in the directory returns fuzzy matches from big plugins.\n     That looks like "your name loses" and is evidence of nothing — only compare\n     against plugins that actually exist.\033[0m\n'
fi

# ------------------------------------------------------------ judgement ------
step "Judgement you still have to make"
cat <<'TXT'
  - Does the name say WHAT it does AND IN WHAT CONTEXT? A coined distinctive term is the
    exception — and it must come FIRST, never appended at the end.
  - Would an ordinary user confuse it with anything listed above, from the name alone?
  - Any keyword stuffing in the name, short description or tags?
  - Is any trademark-looking coined word actually yours? If not, expect to justify it.
  - Is this a Lite/Free edition of a product sold elsewhere? Then the pre-review will read
    the paid product as ANOTHER ENTITY'S unless ownership is provable: TXT record
    wordpressorg-<username>-verification on that product's domain, or an account email on
    it, and Plugin URI / Author URI pointing there. "Lite" itself is allowed.
TXT

echo
if [ "$FAIL" = "0" ]; then
  printf '\033[32m✓ no blocking name problem found\033[0m — the judgement calls above are still yours.\n'
  exit 0
fi
printf '\033[31m✗ fix the name before anything else\033[0m — the slug cannot be changed after approval.\n'
exit 1
