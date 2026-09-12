// Builds docs/help/{en,fr}/*.md into the helpCenter static resource.
// `node scripts/help/build.mjs` writes the resource; `--check` rebuilds into
// a temp folder and exits 1 if the committed resource differs or the
// content breaks a rule (slug missing in one language, hint over 240 chars,
// duplicate order, disallowed tag).
import { marked } from "marked";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  ".."
);
const SRC = path.join(ROOT, "docs", "help");
const OUT = path.join(
  ROOT,
  "force-app",
  "main",
  "default",
  "staticresources",
  "helpCenter"
);
const LANGS = ["en", "fr"];
const HINT_MAX = 240;
const ALLOWED = new Set([
  "h2",
  "h3",
  "p",
  "strong",
  "em",
  "code",
  "a",
  "ul",
  "ol",
  "li",
  "table",
  "thead",
  "tbody",
  "tr",
  "th",
  "td",
  "br"
]);

marked.use({ gfm: true });

function frontMatter(text, file) {
  const m = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/.exec(text);
  if (!m) throw new Error(`${file}: missing front matter`);
  const meta = {};
  for (const line of m[1].split("\n")) {
    const i = line.indexOf(":");
    if (i < 0) throw new Error(`${file}: bad front matter line "${line}"`);
    meta[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  for (const key of ["title", "order", "hint"]) {
    if (!meta[key]) throw new Error(`${file}: front matter needs ${key}`);
  }
  const order = Number(meta.order);
  if (!Number.isInteger(order))
    throw new Error(`${file}: order must be an integer`);
  if ([...meta.hint].length > HINT_MAX) {
    throw new Error(
      `${file}: hint is ${[...meta.hint].length} chars, max ${HINT_MAX}`
    );
  }
  return { title: meta.title, order, hint: meta.hint, body: m[2] };
}

// Keeps only the allowed tags; on <a>, keeps only a safe href. Content is
// repo-authored, so this is a guard against mistakes, not an attacker.
function sanitize(html, file) {
  return html
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<\/?([a-zA-Z0-9]+)([^>]*)>/g, (tag, name, attrs) => {
      const lower = name.toLowerCase();
      if (!ALLOWED.has(lower))
        throw new Error(`${file}: tag <${lower}> is not allowed`);
      if (tag.startsWith("</")) return `</${lower}>`;
      if (lower !== "a") return `<${lower}>`;
      const href = /href="([^"]*)"/.exec(attrs);
      const value = href ? href[1] : "";
      if (!/^(#|\/(?!\/)|https:\/\/)/.test(value))
        throw new Error(
          `${file}: link "${value}" must start with #, / or https://`
        );
      return `<a href="${value}">`;
    });
}

async function readLang(lang) {
  const dir = path.join(SRC, lang);
  const files = (await fs.readdir(dir)).filter((f) => f.endsWith(".md")).sort();
  const entries = await Promise.all(
    files.map(async (f) => {
      const text = await fs.readFile(path.join(dir, f), "utf8");
      const parsed = frontMatter(text, `${lang}/${f}`);
      return [
        f.replace(/\.md$/, ""),
        {
          ...parsed,
          html: sanitize(marked.parse(parsed.body), `${lang}/${f}`)
        }
      ];
    })
  );
  return new Map(entries);
}

async function build(outDir) {
  const byLang = {};
  await Promise.all(
    LANGS.map(async (lang) => {
      byLang[lang] = await readLang(lang);
    })
  );
  const slugs = [...byLang.en.keys()];
  for (const lang of LANGS) {
    const missing = slugs.filter((s) => !byLang[lang].has(s));
    const extra = [...byLang[lang].keys()].filter((s) => !byLang.en.has(s));
    if (missing.length || extra.length) {
      throw new Error(
        `${lang}: missing ${missing.join(",") || "-"}; extra ${extra.join(",") || "-"}`
      );
    }
  }
  const sections = slugs
    .map((slug) => ({
      slug,
      order: byLang.en.get(slug).order,
      title: Object.fromEntries(
        LANGS.map((l) => [l, byLang[l].get(slug).title])
      ),
      hint: Object.fromEntries(LANGS.map((l) => [l, byLang[l].get(slug).hint]))
    }))
    .sort((a, b) => a.order - b.order);
  const orders = new Set();
  for (const s of sections) {
    if (orders.has(s.order)) throw new Error(`order ${s.order} is used twice`);
    orders.add(s.order);
    if (byLang.fr.get(s.slug).order !== s.order)
      throw new Error(`${s.slug}: order differs between languages`);
  }
  await fs.rm(outDir, { recursive: true, force: true });
  await fs.mkdir(outDir, { recursive: true });
  await fs.writeFile(
    path.join(outDir, "index.json"),
    JSON.stringify({ sections }, null, 2) + "\n"
  );
  await Promise.all(
    LANGS.map(async (lang) => {
      await fs.mkdir(path.join(outDir, lang), { recursive: true });
      await Promise.all(
        slugs.map((slug) =>
          fs.writeFile(
            path.join(outDir, lang, `${slug}.html`),
            byLang[lang].get(slug).html
          )
        )
      );
    })
  );
  return sections.length;
}

async function tree(dir) {
  async function walk(d, rel) {
    const entries = (await fs.readdir(d, { withFileTypes: true })).sort(
      (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)
    );
    const lists = await Promise.all(
      entries.map(async (e) => {
        const p = path.join(d, e.name);
        const r = rel ? `${rel}/${e.name}` : e.name;
        if (e.isDirectory()) return walk(p, r);
        return [[r, await fs.readFile(p, "utf8")]];
      })
    );
    return lists.flat();
  }
  return new Map(await walk(dir, ""));
}

async function check() {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "helpCenter-"));
  await build(tmp);
  const [want, have] = await Promise.all([tree(tmp), tree(OUT)]);
  const problems = [];
  for (const [file, content] of want) {
    if (!have.has(file)) problems.push(`missing: ${file}`);
    else if (have.get(file) !== content) problems.push(`stale: ${file}`);
  }
  for (const file of have.keys())
    if (!want.has(file)) problems.push(`extra: ${file}`);
  await fs.rm(tmp, { recursive: true, force: true });
  if (problems.length) {
    console.error(
      `helpCenter is out of date - run npm run help:build\n${problems.join("\n")}`
    );
    process.exit(1);
  }
  console.log("helpCenter is up to date");
}

if (process.argv.includes("--check")) {
  await check();
} else {
  const n = await build(OUT);
  console.log(`built ${n} sections into ${path.relative(ROOT, OUT)}`);
}
