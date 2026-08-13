#!/usr/bin/env node
// cascade-diff — stylesheet-level parity for a migrated page.
//
// Renders the SAME markup twice in one engine at one viewport, changing ONLY the global stylesheet
// (legacy's compiled CSS vs the migrated app's), and diffs getComputedStyle across every node.
// See templates/cascade-diff.md for the technique, the invariant and the font trap.
//
// Needs legacy's compiled CSS, NOT a running legacy host — which is the point: it is available in
// exactly the situations where fm-parity is blocked.
//
// Usage:
//   node cascade-diff.mjs \
//     --legacy-css http://localhost:4204/styles.css \
//     --target-css http://localhost:30221/app/app.css \
//     --markup "apps/web-mobile/app/components/terms/__golden__/terms-100060-*.html" \
//     --out docs/migration/mobile/privacy/cascade-diff.json \
//     [--device "Pixel 7"] [--keep-fonts] [--props a,b,c] [--container-class cms-html]
//
// --container-class applies a class to the TARGET root only. Use it only when the migration really
// applies that class there, and say so in the report — otherwise it is a second loose variable.
import { chromium, devices } from "playwright";
import fs from "node:fs";
import path from "node:path";

// ── args ────────────────────────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const flag = (name, fallback = undefined) => {
  const i = argv.indexOf(`--${name}`);
  return i === -1 ? fallback : argv[i + 1];
};
const bool = (name) => argv.includes(`--${name}`);

const legacyCssArg = flag("legacy-css");
const targetCssArg = flag("target-css");
const markupGlob = flag("markup");
const outPath = flag("out");
const deviceName = flag("device", "Pixel 7");
const containerClass = flag("container-class", "");
const keepFonts = bool("keep-fonts");

if (!legacyCssArg || !targetCssArg || !markupGlob) {
  console.error("cascade-diff: --legacy-css, --target-css and --markup are all required.");
  process.exit(2);
}

// The properties a document's appearance actually rests on. Not "all properties" — getComputedStyle
// enumerates hundreds, most derived or irrelevant, and the noise buries the signal.
// fontFamily is in here ON PURPOSE: it is the tripwire for the font trap (templates/cascade-diff.md).
const DEFAULT_PROPS = [
  "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth",
  "borderTopStyle", "borderTopColor", "borderCollapse",
  "marginTop", "marginRight", "marginBottom", "marginLeft",
  "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
  "display", "width", "boxSizing",
  "fontSize", "fontWeight", "fontFamily", "lineHeight", "letterSpacing",
  "textAlign", "verticalAlign", "textDecorationLine", "textTransform",
  "color", "backgroundColor",
  "whiteSpace", "wordBreak", "overflowWrap", "listStyleType",
];
const PROPS = flag("props") ? flag("props").split(",").map((s) => s.trim()) : DEFAULT_PROPS;

// ── stylesheet loading ──────────────────────────────────────────────────────────────────────────
async function loadCss(src, label) {
  let raw;
  if (/^https?:\/\//.test(src)) {
    const res = await fetch(src);
    if (!res.ok) throw new Error(`${label}: ${src} returned ${res.status}`);
    raw = await res.text();
  } else {
    raw = fs.readFileSync(src, "utf8");
  }

  // Vite serves CSS wrapped in a JS module. JSON.parse unescapes the string literal correctly —
  // hand-rolled unescaping gets \n, \" and unicode wrong and silently corrupts selectors.
  const m = raw.match(/const __vite__css = ("[\s\S]*?")\n/);
  const css = m ? JSON.parse(m[1]) : raw;

  // A stylesheet this small is an error page or a stub, not a cascade. Diffing against nothing makes
  // every rule on the other side look like an addition — which reads as a pass in the wrong direction.
  if (css.length < 2048) {
    throw new Error(
      `${label}: only ${css.length} bytes from ${src}. That is not a compiled stylesheet — ` +
        `check the server is up and the URL is the real sheet.`,
    );
  }
  if (/^\s*[@$]|@use\s|@forward\s|^\s*\$[\w-]+\s*:/m.test(css) && /@use|@forward|^\s*\$/m.test(css)) {
    throw new Error(`${label}: looks like uncompiled SCSS. Point at build output, not source.`);
  }
  return { css, src, bytes: css.length };
}

// ── markup ──────────────────────────────────────────────────────────────────────────────────────
function resolveMarkup(globArg) {
  const dir = path.dirname(globArg);
  const pattern = path.basename(globArg);
  if (!pattern.includes("*")) return [globArg];
  const rx = new RegExp("^" + pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$");
  return fs
    .readdirSync(dir)
    .filter((f) => rx.test(f))
    .sort()
    .map((f) => path.join(dir, f));
}

// ── the two renders ─────────────────────────────────────────────────────────────────────────────
// THE INVARIANT: exactly one variable changes between them — the stylesheet. Markup, engine,
// viewport, DPR, lang and font stack are held identical. A second loose variable makes the report
// noise, and noise sends someone to port an innocent rule.
const FONT_NEUTRALISER = `<style>#root, #root * { font-family: Arial, sans-serif !important }</style>`;

// The <html> element carries BOTH language conventions, on BOTH sides: the `lang` attribute and a
// `lang-xx` class. Apps disagree about which one their per-language rules hang off — the OMH-848
// pair had legacy on `html.lang-zh` and the migrated app on `html[lang="zh"]` — and a host document
// that reproduces only one silently disables half of one side's stylesheet. That surfaces as a real
// looking divergence: the first run of this script reported `strong` at 600 vs 700 across 258 ZH
// nodes, which was the harness, not the apps. Setting both is still ONE variable, because both sides
// get both. Override with --lang-class-prefix if the app uses another convention.
function hostDocument(css, markup, { rootClass, lang }) {
  const langClass = `${flag("lang-class-prefix", "lang-")}${lang}`;
  return `<!doctype html><html lang="${lang}" class="${langClass}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>${css}</style>${keepFonts ? "" : FONT_NEUTRALISER}
</head><body class="${langClass}"><div id="root" class="${rootClass}">${markup}</div></body></html>`;
}

async function collect(ctx, css, markup, opts) {
  const page = await ctx.newPage();
  await page.setContent(hostDocument(css, markup, opts), { waitUntil: "load" });
  const rows = await page.evaluate((props) => {
    return [...document.querySelectorAll("#root *")].map((el) => {
      const cs = getComputedStyle(el);
      const rec = { tag: el.tagName.toLowerCase() };
      for (const p of props) rec[p] = cs[p];
      return rec;
    });
  }, PROPS);
  await page.close();
  return rows;
}

// ── run ─────────────────────────────────────────────────────────────────────────────────────────
const legacy = await loadCss(legacyCssArg, "legacy CSS");
const target = await loadCss(targetCssArg, "target CSS");
const files = resolveMarkup(markupGlob);
if (!files.length) throw new Error(`no markup matched ${markupGlob}`);

const browser = await chromium.launch();
const ctx = await browser.newContext({ ...devices[deviceName] });

const divergences = new Map();
let nodesCompared = 0;
const perDoc = [];

for (const file of files) {
  const markup = fs.readFileSync(file, "utf8");
  // The language tag drives per-language font sheets, line breaking and text-transform, so it is
  // part of the held-constant set. Derive it from the filename when it encodes one.
  const lang = (path.basename(file).match(/[-_]([a-z]{2})\.html?$/i) ?? [])[1] ?? "en";

  const L = await collect(ctx, legacy.css, markup, { rootClass: "", lang });
  const T = await collect(ctx, target.css, markup, { rootClass: containerClass, lang });

  if (L.length !== T.length) {
    console.error(`!! ${file}: node count differs (${L.length} vs ${T.length}) — run invalid.`);
    console.error("   Identical markup must yield identical node counts. Something changed the markup.");
    process.exitCode = 1;
    continue;
  }
  nodesCompared += L.length;

  let docDiffs = 0;
  for (let i = 0; i < L.length; i++) {
    for (const p of PROPS) {
      if (L[i][p] === T[i][p]) continue;
      const key = `${L[i].tag}|${p}|${L[i][p]}|${T[i][p]}`;
      const e = divergences.get(key) ?? {
        tag: L[i].tag, property: p, legacy: L[i][p], target: T[i][p], nodes: 0, languages: new Set(),
      };
      e.nodes++;
      e.languages.add(lang.toUpperCase());
      divergences.set(key, e);
      docDiffs++;
    }
  }
  perDoc.push({ file: path.basename(file), lang: lang.toUpperCase(), nodes: L.length, diffs: docDiffs });
}

await browser.close();

const rows = [...divergences.values()]
  .map((e) => ({ ...e, languages: [...e.languages].sort() }))
  .sort((a, b) => b.nodes - a.nodes);

// ── report ──────────────────────────────────────────────────────────────────────────────────────
// The script does NOT classify rows into real / consequence / artifact — that is judgement, and it
// belongs to the agent reading this output (templates/cascade-diff.md → Reading the report).
// It does flag the one signature it can recognise mechanically.
const fontArtifact = rows.find((r) => r.property === "fontFamily" && r.nodes > nodesCompared * 0.5);

console.log(`\ncascade-diff — ${nodesCompared} nodes, ${PROPS.length} properties, ${files.length} document(s)`);
console.log(`  legacy CSS  ${legacy.bytes} bytes  ${legacy.src}`);
console.log(`  target CSS  ${target.bytes} bytes  ${target.src}`);
console.log(`  fonts       ${keepFonts ? "NOT neutralised (--keep-fonts)" : "neutralised identically on both sides"}`);
if (containerClass) console.log(`  container   .${containerClass} applied to the TARGET root only`);
for (const d of perDoc) console.log(`  ${d.lang.padEnd(3)} ${String(d.nodes).padStart(5)} nodes  ${d.diffs} divergent readings`);

if (!rows.length) {
  console.log("\n  0 divergences. The two stylesheets compute identically on this markup.\n");
} else {
  console.log(`\n  ${rows.length} distinct divergences:\n`);
  for (const r of rows) {
    console.log(`   x${String(r.nodes).padStart(4)}  <${r.tag}> ${r.property}`);
    console.log(`          legacy "${r.legacy}"`);
    console.log(`          target "${r.target}"   [${r.languages.join(",")}]`);
  }
}

if (fontArtifact) {
  console.log(
    `\n  ⚠ LIKELY HARNESS ARTIFACT, NOT A FINDING: fontFamily diverges on ${fontArtifact.nodes} of ` +
      `${nodesCompared} nodes.\n    The two sides resolved different fonts, so every width/height row ` +
      `below it is suspect.\n    Fix the harness and re-run before reading anything else. ` +
      `(templates/cascade-diff.md → The font trap)\n`,
  );
}

if (outPath) {
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(
    outPath,
    JSON.stringify(
      {
        heldConstant: {
          engine: `chromium (playwright ${deviceName})`,
          markup: markupGlob,
          fonts: keepFonts ? "NOT neutralised" : "neutralised identically on both sides",
          containerClass: containerClass || null,
        },
        sources: { legacy: { src: legacy.src, bytes: legacy.bytes }, target: { src: target.src, bytes: target.bytes } },
        nodesCompared,
        propsCompared: PROPS.length,
        documents: perDoc,
        divergences: rows,
        likelyFontArtifact: Boolean(fontArtifact),
      },
      null,
      2,
    ),
  );
  console.log(`  → ${outPath}\n`);
}
