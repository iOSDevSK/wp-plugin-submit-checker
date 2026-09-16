#!/usr/bin/env node
/**
 * refresh-catalog.mjs — regenerate this skill's references from Plugin Check source.
 *
 *   node refresh-catalog.mjs <path-to-extracted-plugin-check> [--skill-dir=<dir>]
 *   node refresh-catalog.mjs --download            # fetch the latest from wordpress.org
 *
 * Nothing in the generated references is written from memory. Every fact below is
 * parsed out of the Plugin Check tree you point this at, and the version it read is
 * stamped into each generated block so a stale catalog is visible at a glance.
 *
 * Why a real parser and not a regex: result codes are POSITIONAL arguments
 *   add_result_error_for_file  ( $result, $message, $code, $file, ... )   -> index 2
 *   add_result_warning_for_file( $result, $message, $code, $file, ... )   -> index 2
 *   add_result_message_for_file( $result, $error, $message, $code, ... )  -> index 3
 * and the first quoted string in that argument list usually belongs to the translated
 * message, not the code. A "first quoted string" regex produces garbage (`label`,
 * `path`, `size`, `defer`) and silently misses real codes such as `hidden_files`.
 */

import { readFileSync, writeFileSync, readdirSync, statSync, existsSync, mkdtempSync } from 'node:fs';
import { join, basename, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_SKILL_DIR = join(HERE, '..');

/* ------------------------------------------------------------------ PHP bits */

/** Walk PHP source from `i` (index of an opening delimiter) to its match, honouring
 *  single/double-quoted strings, // # and /* *\/ comments, and nesting. */
function matchDelim(src, i) {
  const open = src[i];
  const close = { '(': ')', '[': ']', '{': '}' }[open];
  if (!close) throw new Error(`not a delimiter at ${i}: ${open}`);
  let depth = 0;
  for (let p = i; p < src.length; p++) {
    const c = src[p];
    if (c === "'" || c === '"') { p = skipString(src, p); continue; }
    if (c === '/' && src[p + 1] === '/') { p = src.indexOf('\n', p); if (p < 0) return src.length - 1; continue; }
    if (c === '#') { p = src.indexOf('\n', p); if (p < 0) return src.length - 1; continue; }
    if (c === '/' && src[p + 1] === '*') { const e = src.indexOf('*/', p + 2); p = e < 0 ? src.length : e + 1; continue; }
    if (c === open) depth++;
    else if (c === close) { depth--; if (depth === 0) return p; }
  }
  return -1;
}

/** From the index of a quote character, return the index of its closing quote. */
function skipString(src, i) {
  const q = src[i];
  for (let p = i + 1; p < src.length; p++) {
    if (src[p] === '\\') { p++; continue; }
    if (src[p] === q) return p;
  }
  return src.length - 1;
}

/** Split an argument list body on TOP-LEVEL commas. */
function splitArgs(body) {
  const out = [];
  let start = 0, depth = 0;
  for (let p = 0; p < body.length; p++) {
    const c = body[p];
    if (c === "'" || c === '"') { p = skipString(body, p); continue; }
    if (c === '/' && body[p + 1] === '/') { p = body.indexOf('\n', p); if (p < 0) break; continue; }
    if (c === '/' && body[p + 1] === '*') { const e = body.indexOf('*/', p + 2); p = e < 0 ? body.length : e + 1; continue; }
    if ('(['.includes(c)) depth++;
    else if (')]'.includes(c)) depth--;
    else if (c === '{') depth++;
    else if (c === '}') depth--;
    else if (c === ',' && depth === 0) { out.push(body.slice(start, p).trim()); start = p + 1; }
  }
  const tail = body.slice(start).trim();
  if (tail !== '') out.push(tail);
  return out;
}

/** Find every call to `name(` and yield its split arguments. */
function* calls(src, name) {
  const re = new RegExp(`(?<![A-Za-z0-9_])${name}\\s*\\(`, 'g');
  let m;
  while ((m = re.exec(src)) !== null) {
    // Skip the declaration itself: `function add_result_error_for_file( ... )`.
    const before = src.slice(Math.max(0, m.index - 20), m.index);
    if (/\\bfunction\\s+$/.test(before)) { re.lastIndex = m.index + name.length; continue; }
    const open = src.indexOf('(', m.index + m[0].length - 1);
    const close = matchDelim(src, open);
    if (close < 0) continue;
    yield { args: splitArgs(src.slice(open + 1, close)), at: m.index };
    re.lastIndex = close;
  }
}

/** Interpret an argument expression as a result code. */
function asCode(expr) {
  if (!expr) return null;
  const e = expr.trim();
  const lit = /^'((?:[^'\\]|\\.)*)'$/.exec(e) || /^"((?:[^"\\]|\\.)*)"$/.exec(e);
  if (lit) return { code: lit[1], kind: 'literal' };
  // 'prefix_' . $something  -> a family of codes
  const cat = /^'((?:[^'\\]|\\.)*)'\s*\./.exec(e);
  if (cat) return { code: cat[1] + '*', kind: 'prefix' };
  if (/^\$/.test(e)) return { code: null, kind: 'dynamic' };
  return { code: null, kind: 'expr' };
}

/** Remove PHP comments, honouring string literals. Inline comments inside an array
 *  literal carry apostrophes and quoted words, which a bare string-literal regex happily
 *  mistakes for entries (that is how `-for-woocommerce` and a fragment of a sentence ended
 *  up in the trademark list). */
function stripComments(src) {
  let out = '';
  for (let p = 0; p < src.length; p++) {
    const c = src[p];
    if (c === "'" || c === '"') { const e = skipString(src, p); out += src.slice(p, e + 1); p = e; continue; }
    if (c === '/' && src[p + 1] === '/') { const e = src.indexOf('\n', p); if (e < 0) break; p = e - 1; out += '\n'; continue; }
    if (c === '#') { const e = src.indexOf('\n', p); if (e < 0) break; p = e - 1; out += '\n'; continue; }
    if (c === '/' && src[p + 1] === '*') { const e = src.indexOf('*/', p + 2); p = (e < 0 ? src.length : e + 1); continue; }
    out += c;
  }
  return out;
}

function readPhp(f) { return readFileSync(f, 'utf8'); }

function walk(dir, out = []) {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (p.endsWith('.php')) out.push(p);
  }
  return out;
}

/* --------------------------------------------------------------- extraction */

function pcpVersion(root) {
  const readme = join(root, 'readme.txt');
  if (existsSync(readme)) {
    const m = /^Stable tag:\s*(\S+)/m.exec(readFileSync(readme, 'utf8'));
    if (m) return m[1];
  }
  const main = join(root, 'plugin.php');
  if (existsSync(main)) {
    const m = /^\s*\*\s*Version:\s*(\S+)/m.exec(readFileSync(main, 'utf8'));
    if (m) return m[1];
  }
  return 'unknown';
}

/** slug -> relative class path, from Default_Check_Repository::register_default_checks(). */
function registeredChecks(root) {
  const src = readPhp(join(root, 'includes/Checker/Default_Check_Repository.php'));
  const map = new Map();
  const re = /'([a-z0-9_]+)'\s*=>\s*new\s+Checks\\([A-Za-z0-9_\\]+)\s*\(\s*\)/g;
  let m;
  while ((m = re.exec(src)) !== null) map.set(m[1], m[2].replace(/\\/g, '/'));
  return map;
}

function checkFacts(file) {
  const src = readPhp(file);
  const facts = {
    file, class: basename(file, '.php'),
    categories: [], stability: null, runtime: false,
    errorCodes: new Set(), warningCodes: new Set(), dynamicCodes: false,
    sniffs: [], standard: null, extensions: null,
    severityNotes: [], description: null, docs: null,
    forcedError: null,
  };

  if (/Traits\\Experimental_Check|use\s+Experimental_Check/.test(src)) facts.stability = 'experimental';
  if (/Traits\\Stable_Check|use\s+Stable_Check/.test(src)) facts.stability = 'stable';
  if (/extends\s+Abstract_Runtime_Check|implements[^{]*\bRuntime_Check\b/.test(src)) facts.runtime = true;

  for (const c of src.matchAll(/Check_Categories::CATEGORY_([A-Z_]+)/g)) {
    const cat = c[1].toLowerCase();
    if (!facts.categories.includes(cat)) facts.categories.push(cat);
  }

  // get_args() -> standard / sniffs / extensions
  const ga = /function\s+get_args\s*\(/.exec(src);
  if (ga) {
    const open = src.indexOf('{', ga.index);
    const body = src.slice(open, matchDelim(src, open) + 1);
    const std = /'standard'\s*=>\s*('([^']*)'|[^,\n]+)/.exec(body);
    if (std) facts.standard = (std[2] ?? std[1]).trim();
    const sn = /'sniffs'\s*=>\s*'([^']*)'/.exec(body);
    if (sn) facts.sniffs = sn[1].split(',').map((s) => s.trim()).filter(Boolean);
    const ext = /'extensions'\s*=>\s*'([^']*)'/.exec(body);
    if (ext) facts.extensions = ext[1];
  }

  // Result codes, positionally.
  const take = (name, idx, bucket) => {
    for (const { args } of calls(src, name)) {
      const c = asCode(args[idx]);
      if (!c) continue;
      if (c.code) bucket.add(c.code);
      else facts.dynamicCodes = true;
    }
  };
  take('add_result_error_for_file', 2, facts.errorCodes);
  take('add_result_warning_for_file', 2, facts.warningCodes);

  // add_result_message_for_file( $result, $error, $message, $code, ... )
  for (const { args } of calls(src, 'add_result_message_for_file')) {
    if (args.length < 4) continue;
    const c = asCode(args[3]);
    if (!c) continue;
    const isErr = /^true$/i.test((args[1] || '').trim());
    const isWarn = /^false$/i.test((args[1] || '').trim());
    if (c.code) {
      if (isErr) facts.errorCodes.add(c.code);
      else if (isWarn) facts.warningCodes.add(c.code);
      else { facts.errorCodes.add(c.code); facts.warningCodes.add(c.code); }
    } else facts.dynamicCodes = true;
  }

  // An override of add_result_message_for_file that rewrites $error / $severity.
  const ov = /protected\s+function\s+add_result_message_for_file\s*\(/.exec(src);
  if (ov) {
    const open = src.indexOf('{', ov.index);
    const body = src.slice(open, matchDelim(src, open) + 1);
    const fe = /\$error\s*=\s*(true|false)\s*;/.exec(body);
    if (fe) facts.forcedError = fe[1] === 'true';
    for (const s of body.matchAll(/\$severity\s*=\s*(\d+)\s*;/g)) {
      if (!facts.severityNotes.includes(s[1])) facts.severityNotes.push(s[1]);
    }
  }

  const desc = /function\s+get_description\s*\([^)]*\)[^{]*\{[\s\S]*?return\s+__\(\s*'((?:[^'\\]|\\.)*)'/.exec(src);
  if (desc) facts.description = desc[1].replace(/\\'/g, "'");
  const docs = /function\s+get_documentation_url\s*\([^)]*\)[^{]*\{[\s\S]*?return\s+__\(\s*'((?:[^'\\]|\\.)*)'/.exec(src);
  if (docs) facts.docs = docs[1];

  return facts;
}

function rulesetRefs(root) {
  const f = join(root, 'phpcs-rulesets/plugin-check.ruleset.xml');
  if (!existsSync(f)) return [];
  return [...readFileSync(f, 'utf8').matchAll(/\bref="([^"]+)"/g)]
    .map((m) => m[1]).filter((r) => !r.startsWith('.'));
}

function customSniffs(root) {
  const dir = join(root, 'includes/PHPCSStandards/PluginCheck/Sniffs');
  const alt = walk(root).filter((p) => /PluginCheck\/Sniffs\/.+Sniff\.php$/.test(p));
  const files = existsSync(dir) ? walk(dir) : alt;
  return files.filter((p) => p.endsWith('Sniff.php')).map((p) => {
    const rel = p.split('PluginCheck/Sniffs/')[1] || basename(p);
    return 'PluginCheck.' + rel.replace(/Sniff\.php$/, '').replace(/\//g, '.');
  }).sort();
}

function trademarks(root) {
  const f = join(root, 'includes/Checker/Checks/Plugin_Repo/Trademarks_Check.php');
  const src = readPhp(f);
  const constArray = (name) => {
    const i = src.indexOf(`const ${name}`);
    if (i < 0) return [];
    const open = src.indexOf('(', i);
    const body = stripComments(src.slice(open + 1, matchDelim(src, open)));
    return [...body.matchAll(/'([^']+)'/g)].map((m) => m[1]);
  };
  const slugs = constArray('TRADEMARK_SLUGS');
  return {
    ordered: slugs,
    anywhere: slugs.filter((s) => !s.endsWith('-')),
    prefixOnly: slugs.filter((s) => s.endsWith('-')),
    forUseExceptions: constArray('FOR_USE_EXCEPTIONS'),
    portmanteaus: constArray('PORTMANTEAUS'),
    allowedPatterns: (() => {
      const m = /\$allowed_patterns\s*=\s*array\(([\s\S]*?)\);/.exec(src);
      return m ? [...stripComments(m[1]).matchAll(/'([^']+)'/g)].map((x) => x[1]) : [];
    })(),
  };
}

/* ------------------------------------------------------------------- render */

function table(rows, head) {
  const widths = head.map((h, i) => Math.max(h.length, ...rows.map((r) => String(r[i] ?? '').length)));
  const line = (cells) => '| ' + cells.map((c, i) => String(c ?? '').padEnd(widths[i])).join(' | ') + ' |';
  return [line(head), '|' + widths.map((w) => '-'.repeat(w + 2)).join('|') + '|', ...rows.map(line)].join('\n');
}

function codeList(set) {
  const a = [...set].sort();
  return a.length ? a.map((c) => '`' + c + '`').join(', ') : '—';
}

/* --------------------------------------------------------------------- main */

function resolveRoot(argv) {
  const pathArg = argv.find((a) => !a.startsWith('--'));
  if (pathArg) {
    const p = existsSync(join(pathArg, 'includes')) ? pathArg : join(pathArg, 'plugin-check');
    if (!existsSync(join(p, 'includes'))) throw new Error(`no Plugin Check tree at ${pathArg}`);
    return p;
  }
  if (!argv.includes('--download')) {
    throw new Error('usage: refresh-catalog.mjs <path-to-plugin-check> | --download');
  }
  const tmp = mkdtempSync(join(tmpdir(), 'pcp-'));
  const zip = join(tmp, 'plugin-check.zip');
  execFileSync('curl', ['-sL', '-o', zip, 'https://downloads.wordpress.org/plugin/plugin-check.zip']);
  execFileSync('unzip', ['-q', '-o', zip, '-d', tmp]);
  return join(tmp, 'plugin-check');
}

const argv = process.argv.slice(2);
const skillDir = (argv.find((a) => a.startsWith('--skill-dir=')) || '').split('=')[1] || DEFAULT_SKILL_DIR;
const root = resolveRoot(argv);
const version = pcpVersion(root);
const stamp = `Generated by \`scripts/refresh-catalog.mjs\` from **Plugin Check ${version}**. Do not edit by hand.`;

const registered = registeredChecks(root);
const checkFiles = walk(join(root, 'includes/Checker/Checks')).filter((p) => /_Check\.php$/.test(p));
const byClassPath = new Map();
for (const f of checkFiles) {
  const rel = f.split('includes/Checker/Checks/')[1].replace(/\.php$/, '');
  byClassPath.set(rel, f);
}

const rows = [];
const details = [];
const seenFiles = new Set();
for (const [slug, clsPath] of [...registered].sort((a, b) => a[0].localeCompare(b[0]))) {
  const file = byClassPath.get(clsPath);
  if (!file) { rows.push([`\`${slug}\``, '?', '?', 'CLASS NOT FOUND', '', '']); continue; }
  seenFiles.add(file);
  const f = checkFacts(file);
  const kind = f.runtime ? 'runtime' : 'static';
  const mech = f.sniffs.length ? f.sniffs.map((s) => '`' + s + '`').join('<br>')
    : f.standard ? '`' + f.standard.replace(/^WP_PLUGIN_CHECK_PLUGIN_DIR_PATH \. /, '') + '`'
    : 'own logic';
  rows.push([
    '`' + slug + '`',
    f.categories.join(', ') || '—',
    kind + (f.stability === 'experimental' ? ', experimental' : ''),
    codeList(f.errorCodes),
    codeList(f.warningCodes),
    mech,
  ]);
  details.push({ slug, ...f, kind });
}

const unregistered = checkFiles.filter((p) => !seenFiles.has(p) && !/Abstract_/.test(basename(p)));

const tm = trademarks(root);
const refs = rulesetRefs(root);
const sniffs = customSniffs(root);
const categories = (() => {
  const src = readPhp(join(root, 'includes/Checker/Check_Categories.php'));
  return [...src.matchAll(/const CATEGORY_[A-Z_]+\s*=\s*'([a-z_]+)'/g)].map((m) => m[1]);
})();
const usedCategories = new Set(details.flatMap((d) => d.categories));

/* ---- D2: plugin-check-catalog.md ---- */
let out = `# Plugin Check — check & result-code catalog

${stamp}

**${registered.size} checks are registered** and therefore runnable. Categories defined:
${categories.map((c) => '`' + c + '`').join(', ')}.

${categories.filter((c) => !usedCategories.has(c)).length
  ? `> **Empty categories:** ${categories.filter((c) => !usedCategories.has(c)).map((c) => '`' + c + '`').join(', ')} — defined in \`Check_Categories\` but **no registered check uses them**, so \`--categories=<that>\` runs nothing. Never present them as covered.`
  : ''}

${unregistered.length
  ? `> **Classes that exist but are NEVER registered** (they do not run, whatever their filename suggests):
${unregistered.map((p) => '> - `' + p.split('includes/Checker/Checks/')[1] + '`').join('\n')}`
  : ''}

> **The \`type: runtime\` checks need two conditions met, and fail silently when they are
> not.** See [runtime-checks.md](runtime-checks.md) — hand-written, survives a refresh.

## All registered checks

${table(rows, ['slug', 'category', 'type', 'error codes', 'warning codes', 'mechanism'])}

## Per-check detail

`;

for (const d of details) {
  out += `### \`${d.slug}\`\n\n`;
  if (d.description) out += `${d.description}\n\n`;
  const meta = [];
  meta.push(`- **Category:** ${d.categories.join(', ') || '—'} · **Type:** ${d.kind} · **Stability:** ${d.stability ?? 'unknown'}`);
  if (d.runtime) meta.push('- **Runtime check** — silently skipped under plain WP-CLI unless you pass `--require=<plugin-check>/cli.php`.');
  if (d.sniffs.length) meta.push(`- **Sniffs:** ${d.sniffs.map((s) => '`' + s + '`').join(', ')}`);
  else if (d.standard) meta.push(`- **PHPCS standard:** \`${d.standard}\``);
  if (d.forcedError === false) meta.push('- **Always reported as a WARNING** — the check overrides `$error = false`, so it can never block the submission form. It is still raised at human review.');
  if (d.forcedError === true) meta.push('- **Always reported as an ERROR** — the check overrides `$error = true`.');
  if (d.severityNotes.length) meta.push(`- **Severity overridden to:** ${d.severityNotes.join(', ')} (default is 5)`);
  if (d.dynamicCodes) meta.push('- Emits codes that are **not literals** in the source (sniff codes, or built at runtime) — the code column above is therefore incomplete for this check by construction. A real run is the authority.');
  if (d.docs) meta.push(`- Docs: ${d.docs}`);
  out += meta.join('\n') + '\n\n';
  const e = [...d.errorCodes].sort(), w = [...d.warningCodes].sort();
  if (e.length) out += `**Errors:** ${e.map((c) => '`' + c + '`').join(', ')}\n\n`;
  if (w.length) out += `**Warnings:** ${w.map((c) => '`' + c + '`').join(', ')}\n\n`;
}

out += `## \`plugin_review_phpcs\` — the sniffs it runs

\`phpcs-rulesets/plugin-review.xml\` wraps \`plugin-check.ruleset.xml\` and adds
\`testVersion 5.2-\` (PHPCompatibility is evaluated from PHP 5.2 up, which is why modern
syntax can surface findings your project's own phpcs never shows) plus exclude-patterns
for common vendored frameworks.

${refs.map((r) => '- `' + r + '`').join('\n')}

## Plugin Check's own sniffs

${sniffs.map((s) => '- `' + s + '`').join('\n')}
`;

writeFileSync(join(skillDir, 'references/plugin-check-catalog.md'), out);

/* ---- generated blocks in the other references ---- */
const blocks = {
  'trademark-lists': `${stamp}

**Matched anywhere in the slug** (no trailing hyphen — \`strpos\`, so the term may not
appear in *any* position):

${tm.anywhere.map((s) => '`' + s + '`').join(' · ')}

**Matched as a prefix only** (trailing hyphen — the slug may not *begin* with it):

${tm.prefixOnly.map((s) => '`' + s + '`').join(' · ')}

**\`FOR_USE_EXCEPTIONS\`** — the only trademarks the "for/with" escape hatch applies to:

${tm.forUseExceptions.map((s) => '`' + s + '`').join(', ') || '— (none)'}

Accepted patterns around such a term: ${tm.allowedPatterns.map((s) => '`' + s + '`').join(', ')}.
After the pattern is removed the term must not appear anywhere else in the slug, so
\`mcp-for-woocommerce\` passes and \`woo-mcp-for-woocommerce\` does not.

**\`PORTMANTEAUS\`** — blocked blends (e.g. \`woopress\`): ${tm.portmanteaus.map((s) => '`' + s + '`').join(', ') || '—'}`,

  'header-codes': `${stamp}

${(() => {
  const h = details.find((d) => d.slug === 'plugin_header_fields');
  const r = details.find((d) => d.slug === 'plugin_readme');
  const fmt = (d) => d ? `**\`${d.slug}\` errors:** ${codeList(d.errorCodes)}\n\n**\`${d.slug}\` warnings:** ${codeList(d.warningCodes)}` : '';
  return [fmt(h), fmt(r)].filter(Boolean).join('\n\n');
})()}`,

  'file-type-codes': `${stamp}

${(() => {
  const d = details.find((x) => x.slug === 'file_type');
  const p = details.find((x) => x.slug === 'plugin_content');
  const fmt = (x) => x ? `**\`${x.slug}\` errors:** ${codeList(x.errorCodes)}\n\n**\`${x.slug}\` warnings:** ${codeList(x.warningCodes)}` : '';
  return [fmt(d), fmt(p)].filter(Boolean).join('\n\n');
})()}`,

  'runtime-checks': `${stamp}

These checks extend \`Abstract_Runtime_Check\` and are **silently skipped** under plain
WP-CLI unless \`--require=<plugin-check>/cli.php\` is passed:

${details.filter((d) => d.runtime).map((d) => '- `' + d.slug + '`').join('\n') || '- (none)'}`,
};

for (const f of ['naming-and-trademarks.md', 'readme-and-headers.md', 'distribution-payload.md', 'plugin-check-catalog.md']) {
  const p = join(skillDir, 'references', f);
  if (!existsSync(p)) continue;
  let txt = readFileSync(p, 'utf8');
  let changed = false;
  for (const [key, body] of Object.entries(blocks)) {
    const re = new RegExp(`(<!-- GENERATED:start:${key} -->)[\\s\\S]*?(<!-- GENERATED:end:${key} -->)`);
    if (re.test(txt)) { txt = txt.replace(re, `$1\n${body}\n$2`); changed = true; }
  }
  if (changed) writeFileSync(p, txt);
}

// Data file for scripts/name-check.sh. The ORDER matters: has_trademarked_slug() breaks
// on the first match, so which entry is found first changes the message the author gets.
// Trailing hyphen = prefix test; no hyphen = matched anywhere.
writeFileSync(join(skillDir, 'scripts/trademark-slugs.txt'),
  `# Generated from Plugin Check ${version} — Trademarks_Check. Do not edit.\n` +
  `# Order is significant: the check breaks on the first match.\n` +
  `[TRADEMARK_SLUGS]\n${tm.ordered.join('\n')}\n` +
  `[FOR_USE_EXCEPTIONS]\n${tm.forUseExceptions.join('\n')}\n` +
  `[ALLOWED_PATTERNS]\n${tm.allowedPatterns.join('\n')}\n` +
  `[PORTMANTEAUS]\n${tm.portmanteaus.join('\n')}\n`);

console.log(`Plugin Check ${version}`);
console.log(`  registered checks : ${registered.size}`);
console.log(`  unregistered classes: ${unregistered.length}${unregistered.length ? ' (' + unregistered.map((p) => basename(p)).join(', ') + ')' : ''}`);
console.log(`  error codes       : ${details.reduce((n, d) => n + d.errorCodes.size, 0)}`);
console.log(`  warning codes     : ${details.reduce((n, d) => n + d.warningCodes.size, 0)}`);
console.log(`  ruleset refs      : ${refs.length}`);
console.log(`  own sniffs        : ${sniffs.length}`);
console.log(`  trademark slugs   : ${tm.anywhere.length} anywhere + ${tm.prefixOnly.length} prefix-only`);
console.log(`  wrote             : references/plugin-check-catalog.md, scripts/trademark-slugs.txt`);
