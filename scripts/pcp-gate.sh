#!/usr/bin/env bash
# pcp-gate.sh — run Plugin Check the way wordpress.org runs it, against the payload
# that will actually be submitted, in a throwaway WordPress.
#
#   pcp-gate.sh <plugin-dir|plugin.zip> [options]
#
#   --slug=<slug>     plugin slug (default: the directory/archive-root name)
#   --mode=new        'new' (default, first submission) or 'update'
#   --self-test       prove the checker is really running before trusting a clean run
#   --json=<file>     write the raw Plugin Check JSON here
#   --keep            leave the containers up for poking
#   --port=<n>        host port (default 8896)
#
# Why each non-obvious flag is here — every one of these has produced a false pass:
#
#   * The plugin is installed as wp-content/plugins/<slug>/. Plugin Check will read a
#     path, but a directory named anything other than the slug produces a flood of
#     bogus textdomain_mismatch errors.
#   * --mode=new. In 'new' mode an outdated "Tested up to" is an ERROR; in 'update'
#     the same finding is only a warning. A first submission is checked as 'new'.
#   * --require=<plugin-check>/cli.php. The five Abstract_Runtime_Check subclasses are
#     SILENTLY SKIPPED under plain WP-CLI without it. A run without it is not a run.
#   * --include-low-severity-errors / --include-low-severity-warnings, and no exclude
#     flags at all. wordpress.org does not honour your exclusions.
#   * --self-test. A checker that failed to load looks exactly like a clean plugin.
#
# Network is required: plugin_readme fetches the current WordPress version,
# plugin_header_fields validates each "Requires Plugins" entry against the directory,
# and wp_functions_compatibility needs the bundled since-data. Offline they degrade
# quietly rather than failing.
#
# Offline Plugin Check: set PLUGIN_CHECK_ZIP=/path/to/plugin-check.zip
set -uo pipefail

SRC=""; SLUG=""; MODE="new"; SELFTEST=0; JSONOUT=""; KEEP=0; PORT=8896
for a in "$@"; do
  case "$a" in
    --slug=*)  SLUG="${a#*=}" ;;
    --mode=*)  MODE="${a#*=}" ;;
    --json=*)  JSONOUT="${a#*=}" ;;
    --port=*)  PORT="${a#*=}" ;;
    --self-test) SELFTEST=1 ;;
    --keep)    KEEP=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    -*) echo "unknown option: $a" >&2; exit 2 ;;
    *) SRC="$a" ;;
  esac
done

NET=pcpgate-net; DB=pcpgate-db; WP=pcpgate-wp
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
die()  { printf '\n\033[31mGATE ABORTED: %s\033[0m\n' "$*" >&2; exit 2; }

[ -n "$SRC" ] || die "usage: pcp-gate.sh <plugin-dir|plugin.zip> [--slug=…] [--mode=new|update] [--self-test]"
[ -e "$SRC" ] || die "no such path: $SRC"
case "$MODE" in new|update) ;; *) die "--mode must be 'new' or 'update'";; esac
command -v docker >/dev/null || die "docker is required"
docker info >/dev/null 2>&1 || die "docker is installed but not running"

cleanup() {
  if [ "$KEEP" = "1" ]; then
    echo; echo "containers left running: $WP (port $PORT), $DB — remove with:"
    echo "  docker rm -f $WP $DB && docker network rm $NET"
  else
    docker rm -f "$WP" "$DB" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1
  fi
}
trap cleanup EXIT

# ------------------------------------------------------------------ payload ---
step "Payload"
PKG="$(mktemp -d)"
if [ -d "$SRC" ]; then
  BASE="$(basename "$(cd "$SRC" && pwd)")"
  [ -n "$SLUG" ] || SLUG="$BASE"
  mkdir -p "$PKG/$SLUG" && cp -R "$SRC"/. "$PKG/$SLUG"/
  pass "copied directory $BASE -> $SLUG/"
else
  ( cd "$PKG" && unzip -q "$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")" ) || die "could not unpack $SRC"
  ROOT="$(find "$PKG" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [ -n "$ROOT" ] || die "the archive has no directory at its root"
  [ -n "$SLUG" ] || SLUG="$(basename "$ROOT")"
  [ "$(basename "$ROOT")" = "$SLUG" ] || mv "$ROOT" "$PKG/$SLUG"
  pass "unpacked archive -> $SLUG/"
fi
# A ZIP sitting inside the tree trips file_type/compressed_files. Ours is outside.
find "$PKG/$SLUG" -maxdepth 1 -name '*.zip' -print | while read -r z; do
  bad "an archive ships inside the payload: $(basename "$z") — file_type will flag it"
done
COUNT=$(find "$PKG/$SLUG" -type f | wc -l | tr -d ' ')
pass "$COUNT files, slug '$SLUG', mode '$MODE'"

# ---------------------------------------------------------------- WordPress ---
step "WordPress"
docker rm -f "$WP" "$DB" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1
docker network create "$NET" >/dev/null || die "could not create the docker network"
docker run -d --name "$DB" --network "$NET" \
  -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=wp mariadb:11 >/dev/null \
  || die "could not start MariaDB"
docker run -d --name "$WP" --network "$NET" -p "$PORT:80" \
  -e WORDPRESS_DB_HOST="$DB" -e WORDPRESS_DB_USER=root \
  -e WORDPRESS_DB_PASSWORD=root -e WORDPRESS_DB_NAME=wp \
  -e WORDPRESS_CONFIG_EXTRA="define('FS_METHOD','direct');" \
  wordpress:latest >/dev/null || die "could not start WordPress"
for _ in $(seq 1 60); do docker exec "$DB" mariadb -uroot -proot -e 'select 1' wp >/dev/null 2>&1 && break; sleep 3; done
for _ in $(seq 1 40); do docker exec "$WP" test -f /var/www/html/wp-load.php && break; sleep 3; done
sleep 5

# Pick a WP-CLI image that is ALREADY LOCAL before reaching for the registry. A blind
# `docker run wordpress:cli` blocks on a registry pull that can hang for many minutes and
# is indistinguishable, from the outside, from a slow WordPress boot.
CLI_IMAGE="${PCPGATE_CLI_IMAGE:-}"
if [ -z "$CLI_IMAGE" ]; then
  for CAND in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^wordpress:cli' | head -5); do
    CLI_IMAGE="$CAND"; break
  done
fi
if [ -z "$CLI_IMAGE" ]; then
  CLI_IMAGE=wordpress:cli
  echo "  pulling $CLI_IMAGE (no local wordpress:cli image found)…"
  timeout 300 docker pull -q "$CLI_IMAGE" >/dev/null 2>&1 \
    || die "could not pull $CLI_IMAGE. Pull it once by hand (docker pull wordpress:cli) or point PCPGATE_CLI_IMAGE at a local WP-CLI image."
fi
pass "WP-CLI image: $CLI_IMAGE"

wpcli() {
  docker run --rm --network "$NET" --volumes-from "$WP" -u 33:33 \
    -e WORDPRESS_DB_HOST="$DB" -e WORDPRESS_DB_USER=root \
    -e WORDPRESS_DB_PASSWORD=root -e WORDPRESS_DB_NAME=wp \
    "$CLI_IMAGE" wp "$@" 2>&1
}
wpcli core install --url="http://localhost:$PORT" --title=PCPGate \
  --admin_user=admin --admin_password=admin --admin_email=a@example.com --skip-email >/dev/null \
  || die "WordPress would not install"
pass "WordPress $(wpcli core version) up"

docker cp "$PKG/$SLUG" "$WP:/var/www/html/wp-content/plugins/$SLUG" >/dev/null \
  || die "could not copy the payload into the container"
docker exec "$WP" chown -R www-data:www-data "/var/www/html/wp-content/plugins/$SLUG"
pass "installed as wp-content/plugins/$SLUG"

# -------------------------------------------------------------- Plugin Check ---
step "Plugin Check"
if ! wpcli plugin is-installed plugin-check >/dev/null 2>&1; then
  if [ -n "${PLUGIN_CHECK_ZIP:-}" ]; then
    [ -f "$PLUGIN_CHECK_ZIP" ] || die "PLUGIN_CHECK_ZIP is set but does not exist: $PLUGIN_CHECK_ZIP"
    # The WP-CLI container shares only the WordPress volume with $WP, so a file dropped
    # in the WP container's /tmp is invisible to it. Stage inside the shared volume.
    docker cp "$PLUGIN_CHECK_ZIP" "$WP:/var/www/html/pcpgate-plugin-check.zip" >/dev/null
    docker exec "$WP" chown www-data:www-data /var/www/html/pcpgate-plugin-check.zip
    INSTALL_OUT="$(wpcli plugin install /var/www/html/pcpgate-plugin-check.zip --activate)"
    docker exec "$WP" rm -f /var/www/html/pcpgate-plugin-check.zip
    printf '%s' "$INSTALL_OUT" | grep -qi "success\|already installed" \
      || { echo "$INSTALL_OUT" | sed 's/^/    /' | head -10; die "could not install Plugin Check from the ZIP"; }
  else
    wpcli plugin install plugin-check --activate >/dev/null \
      || die "could not install Plugin Check from wordpress.org — retry online, or re-run with PLUGIN_CHECK_ZIP=/path/to/plugin-check.zip"
  fi
fi
wpcli plugin activate plugin-check >/dev/null 2>&1
wpcli plugin is-active plugin-check >/dev/null 2>&1 || die "Plugin Check did not activate — every result below would be a lie"
PCPVER="$(wpcli plugin get plugin-check --field=version)"
pass "Plugin Check $PCPVER"

CLI_BOOTSTRAP=/var/www/html/wp-content/plugins/plugin-check/cli.php
docker exec "$WP" test -f "$CLI_BOOTSTRAP" \
  || bad "no cli.php at $CLI_BOOTSTRAP — runtime checks will be skipped"

# ------------------------------------------------------------ runtime checks ---
# Abstract_Check_Runner::allow_runtime_checks() is:
#
#     ( $this->initialized_early || $this->runtime_environment->can_set_up() )
#         && is_plugin_active( $this->get_plugin_basename() )
#
# TWO independent conditions, and missing either one skips the five runtime checks in
# complete silence — the run simply reports fewer findings:
#
#   1. --require=<plugin-check>/cli.php, placed AFTER "plugin check" (see run_check).
#   2. THE PLUGIN UNDER TEST MUST BE ACTIVE. Copying it into the plugins directory is
#      not enough.
step "Runtime checks"
ACT_OUT="$(wpcli plugin activate "$SLUG")"
RUNTIME_OK=0
if printf '%s' "$ACT_OUT" | grep -qi "success\|already active"; then
  pass "activated $SLUG"
else
  bad "could not activate $SLUG — the five runtime checks cannot run"
  printf '%s' "$ACT_OUT" | sed 's/^/      /' | head -5
fi

# Probe, rather than assume: if runtime checks are not available the runner does not
# merely return nothing, it refuses the slug outright. That makes a cheap, deterministic
# test with no fixture needed.
PROBE="$(wpcli plugin check "$SLUG" --require="$CLI_BOOTSTRAP" --checks=enqueued_scripts_size --format=json 2>&1)"
if printf '%s' "$PROBE" | grep -q 'does not exist'; then
  bad "runtime checks are NOT running (the runner refuses 'enqueued_scripts_size')"
  echo "      enqueued_scripts_size, enqueued_styles_size, enqueued_scripts_scope,"
  echo "      enqueued_styles_scope and non_blocking_scripts will be missing from the run."
else
  pass "runtime checks are live (enqueued_scripts_size resolves)"
  RUNTIME_OK=1
fi

# --require MUST come AFTER "plugin check", not before it.
#
# cli.php installs the object-cache drop-in that runtime checks need, but only when
# CLI_Runner::is_plugin_check() says so — and that function tests
#     $_SERVER['argv'][1] === 'plugin' && $_SERVER['argv'][2] === 'check'
# So `wp --require=... plugin check X` shifts argv, the test fails, the drop-in is never
# installed, and the five runtime checks are SILENTLY SKIPPED. The run looks completely
# normal and reports fewer findings. Putting the global parameter in its natural place
# disables the exact thing it was passed for.
run_check() {  # run_check <extra-args...>
  wpcli plugin check "$SLUG" --require="$CLI_BOOTSTRAP" \
    --mode="$MODE" \
    --include-low-severity-errors --include-low-severity-warnings \
    --format=json "$@"
}

step "Check run"
RAW="$(mktemp)"
run_check > "$RAW"
if ! grep -qE '^FILE:|^\[' "$RAW"; then
  echo "  --- Plugin Check output ---"; sed 's/^/  /' "$RAW" | head -30
  die "Plugin Check produced no parsable result"
fi

# Did the runtime checks actually run? Their absence is invisible in the output itself.
RUNTIME_SLUGS="enqueued_scripts_size enqueued_styles_size enqueued_scripts_scope enqueued_styles_scope non_blocking_scripts"

COUNTS="$(mktemp)"
python3 - "$RAW" "$SLUG" "$MODE" "$PCPVER" "${JSONOUT:-}" "$COUNTS" <<'PY'
import json, re, sys, collections, html

raw, slug, mode, ver, jsonout, counts = (sys.argv + ['', ''])[1:7]
text = open(raw, encoding='utf-8', errors='replace').read()

# `wp plugin check --format=json` does NOT emit one JSON document. It emits a sequence of
#     FILE: <relative path>
#     [ {...}, {...} ]
# blocks, one per file with findings. Parsing it as a single array silently yields nothing.
rows = []
blocks = re.split(r'^FILE:[ \t]*', text, flags=re.M)
if len(blocks) > 1:
    for b in blocks[1:]:
        nl = b.find('\n')
        fname, body = (b[:nl].strip(), b[nl + 1:]) if nl >= 0 else (b.strip(), '')
        m = re.search(r'\[.*\]', body, re.S)
        if not m:
            continue
        try:
            items = json.loads(m.group(0))
        except Exception:
            continue
        for it in items:
            it['file'] = fname
            rows.append(it)
else:
    m = re.search(r'\[.*\]', text, re.S)
    if m:
        try:
            got = json.loads(m.group(0))
            rows = got if isinstance(got, list) else got.get(slug, [])
        except Exception:
            rows = []

for r in rows:
    if isinstance(r.get('message'), str):
        r['message'] = html.unescape(r['message'])

err  = [r for r in rows if str(r.get('type', '')).upper() == 'ERROR']
warn = [r for r in rows if str(r.get('type', '')).upper() == 'WARNING']

def group(rs):
    g = collections.defaultdict(list)
    for r in rs:
        g[r.get('code') or '(no code)'].append(r)
    return sorted(g.items(), key=lambda kv: (-len(kv[1]), kv[0]))

def show(title, rs, colour):
    if not rs:
        return
    print(f"\n  \033[1m{title}\033[0m — {len(rs)} finding(s) across {len(group(rs))} code(s)")
    for code, items in group(rs):
        print(f"    \033[{colour}m{len(items):>3}x\033[0m  {code}")
        for it in items[:3]:
            loc = f"{it.get('file','')}:{it.get('line','')}"
            msg = ' '.join(str(it.get('message', '')).split())[:100]
            print(f"           {loc}  {msg}")
        if len(items) > 3:
            print(f"           … and {len(items)-3} more")

print(f"\n  Plugin Check {ver} · mode={mode} · slug={slug} · {len(rows)} finding(s) parsed")
show('ERRORS', err, '31')
show('WARNINGS', warn, '33')

if jsonout:
    json.dump({'slug': slug, 'mode': mode, 'plugin_check_version': ver,
               'errors': err, 'warnings': warn}, open(jsonout, 'w'), indent=2)
    print(f"\n  normalised JSON -> {jsonout}")

open(counts, 'w').write(f"{len(err)} {len(warn)}")
PY

read -r NERR NWARN < "$COUNTS"

# ---------------------------------------------------------------- self-test ---
if [ "$SELFTEST" = "1" ]; then
  step "Self-test (is the checker actually running?)"
  docker exec "$WP" sh -c "printf '%s' '<?php echo \$_GET[\"x\"]; ' > /var/www/html/wp-content/plugins/$SLUG/pcpgate-canary.php"
  docker exec "$WP" chown www-data:www-data "/var/www/html/wp-content/plugins/$SLUG/pcpgate-canary.php"
  CANARY="$(run_check --checks=late_escaping 2>/dev/null | grep -c 'pcpgate-canary' || true)"
  docker exec "$WP" rm -f "/var/www/html/wp-content/plugins/$SLUG/pcpgate-canary.php"
  if [ "${CANARY:-0}" -gt 0 ]; then
    pass "injected unescaped output was flagged — the run above is real"
  else
    bad "the injected canary was NOT flagged"
    die "Plugin Check is not actually inspecting this plugin. A clean run here means nothing."
  fi
fi

# ------------------------------------------------------------------ verdict ---
step "Verdict"
echo "  Rule: zero ERRORS is the hard gate. Every remaining WARNING must be either"
echo "  fixed or written down in the report with a justification."
echo
if [ "$NERR" = "0" ]; then
  if [ "$NWARN" = "0" ]; then
    printf '\033[32m✓ GATE PASSED\033[0m — 0 errors, 0 warnings.\n'
  else
    printf '\033[32m✓ GATE PASSED\033[0m — 0 errors, \033[33m%s warning(s)\033[0m left to justify.\n' "$NWARN"
  fi
  [ "$SELFTEST" = "1" ] || printf '\033[33m  note:\033[0m re-run with --self-test before trusting this.\n'
  [ "$RUNTIME_OK" = "1" ] || printf '\033[33m  note:\033[0m runtime checks did NOT run — this is a partial result.\n'
  exit 0
fi
printf '\033[31m✗ GATE FAILED\033[0m — %s error(s). wordpress.org will refuse the upload.\n' "$NERR"
exit 1
