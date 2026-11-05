#!/usr/bin/env bash
# Builds the attribution fixture repo in the current (empty) eval workspace.
#
# History (main):
#   c0 "initial"        card + gallery + tests. Local branch `master` is left HERE (stale).
#   c1 "merged change"  someone else's already-merged edit to card.test.tsx. Tagged `pr-base`.
#   c2 "the change"     the change under review:
#     - card.tsx: one clean line (withWidth on the card image). Pre-existing issues stay untouched.
#     - gallery.tsx: sub tiles wrapped in withWidth on a line that ALREADY interpolated the URL
#       into CSS url("...") unescaped (→ expected [touched]); a NEW dangerouslySetInnerHTML caption
#       (→ expected [introduced]).
#     - gallery.test.tsx: new tests using querySelector, like the 6 existing ones (→ convention);
#       thumbnails are <img alt=""> (a getAllByRole("img") fix would not find them).
set -euo pipefail

export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

# test-review resolves Node from the app's .nvmrc via ~/.nvm; give the temp HOME a stand-in.
node_bin="$(command -v node || true)"
if [ -n "$node_bin" ]; then
  mkdir -p "$HOME/.nvm/versions/node/v22.0.0/bin"
  ln -sf "$node_bin" "$HOME/.nvm/versions/node/v22.0.0/bin/node"
fi

git init -q -b main .
mkdir -p .claude app/lib app/components
echo 22 > .nvmrc
cat > .claude/frontend-v2-plugin.json <<'JSON'
{
  "appProfile": "ota",
  "routerMode": "framework",
  "serverState": "tanstack-query",
  "formStack": "native",
  "e2eTool": "playwright",
  "componentLibrary": "external",
  "externalComponents": { "package": "@acme/ui" },
  "apiLayer": "feature-local",
  "clientStore": "none",
  "i18nBinding": "custom-hook",
  "baseDir": "app",
  "appDir": "."
}
JSON

cat > app/lib/with-width.ts <<'TS'
// Appends ?w=800 to image URLs under /img/. Edits the raw string; other characters pass through.
export function withWidth<T extends string | null | undefined>(url: T): T {
  if (!url || !url.includes("/img/")) return url;
  return `${url}${url.includes("?") ? "&" : "?"}w=800` as T;
}
TS

cat > app/components/card.tsx <<'TSX'
import { t } from "../lib/i18n";

type Product = { name: string; imageUrl: string; rating: number | null };

export function Card({ product, language }: { product: Product; language: string }) {
  const hasScore = typeof product.rating === "number" && product.rating > 0;
  return (
    <article className="card">
      <img className="card-image" src={product.imageUrl} alt={`${product.name} - Image 1`} />
      <button type="button" aria-label="Previous image" className="prev" />
      <button type="button" aria-label="Next image" className="next" />
      <h3>{product.name}</h3>
      {hasScore ? <span className="score">{(product.rating as number).toFixed(1)}</span> : null}
      <span>{t(language, "card.view")}</span>
    </article>
  );
}
TSX

cat > app/components/card.test.tsx <<'TSX'
import { render, screen } from "@testing-library/react";
import { Card } from "./card";

const product = { name: "Lamp", imageUrl: "/img/a.jpg", rating: 8.4 };

describe("Card", () => {
  it("shows the name", () => {
    render(<Card product={product} language="en" />);
    expect(screen.getByRole("heading", { name: "Lamp" })).toBeInTheDocument();
  });

  it("shows the score", () => {
    render(<Card product={product} language="en" />);
    expect(screen.getByText("8.4")).toBeInTheDocument();
  });
});
TSX

cat > app/components/gallery.tsx <<'TSX'
type Photo = { url: string | null; caption: string | null };

const FALLBACK = "/assets/no-image.png";

function tileStyle(url: string | null) {
  return { backgroundImage: `url("${url ?? ""}"), url("${FALLBACK}")` };
}

export function Gallery({ photos }: { photos: Photo[] }) {
  const lead = photos[0];
  return (
    <section className="gallery">
      <div className="main-tile" style={tileStyle(lead?.url ?? null)} />
      <ul className="sub-tiles">
        {photos.slice(1, 5).map((p, i) => (
          <li key={i} className="sub-tile" style={tileStyle(p.url)} />
        ))}
      </ul>
      <ul className="thumbs">
        {photos.map((p, i) => (
          <li key={i}>
            <img className="thumb" src={p.url ?? FALLBACK} alt="" />
          </li>
        ))}
      </ul>
    </section>
  );
}
TSX

cat > app/components/gallery.test.tsx <<'TSX'
import { render } from "@testing-library/react";
import { Gallery } from "./gallery";

const photos = [
  { url: "/img/a.jpg", caption: "A" },
  { url: "/img/b.jpg", caption: "B" },
  { url: "/img/c.jpg", caption: "C" },
];

describe("Gallery", () => {
  it("paints the lead photo on the main tile", () => {
    const { container } = render(<Gallery photos={photos} />);
    const tile = container.querySelector(".main-tile") as HTMLElement;
    expect(tile.style.backgroundImage).toContain("/img/a.jpg");
  });

  it("paints up to four sub tiles", () => {
    const { container } = render(<Gallery photos={photos} />);
    expect(container.querySelectorAll(".sub-tile")).toHaveLength(2);
  });

  it("keeps the fallback layer", () => {
    const { container } = render(<Gallery photos={photos} />);
    const tile = container.querySelector(".main-tile") as HTMLElement;
    expect(tile.style.backgroundImage).toContain("/assets/no-image.png");
  });

  it("renders one thumbnail per photo", () => {
    const { container } = render(<Gallery photos={photos} />);
    expect(container.querySelectorAll(".thumbs img")).toHaveLength(3);
  });

  it("uses the fallback for a missing thumbnail url", () => {
    const { container } = render(<Gallery photos={[{ url: null, caption: null }]} />);
    expect(container.querySelector(".thumbs img")?.getAttribute("src")).toBe("/assets/no-image.png");
  });

  it("renders nothing in the sub list for one photo", () => {
    const { container } = render(<Gallery photos={photos.slice(0, 1)} />);
    expect(container.querySelectorAll(".sub-tile")).toHaveLength(0);
  });
});
TSX

export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
git add -A && git commit -q -m "initial"
git branch master   # stale local branch, left at c0

# c1 — an already-merged change by someone else (NOT part of the change under review)
python3 - <<'PY'
import pathlib
p = pathlib.Path("app/components/card.test.tsx")
s = p.read_text().replace('expect(screen.getByText("8.4")).toBeInTheDocument();',
                          'expect(screen.getByText("8.4")).toHaveClass("score");')
p.write_text(s)
PY
export GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" GIT_COMMITTER_DATE="2026-01-02T00:00:00Z"
git commit -q -am "merged change: assert the score class"
git tag pr-base

# c2 — the change under review
python3 - <<'PY'
import pathlib
c = pathlib.Path("app/components/card.tsx"); s = c.read_text()
s = s.replace('import { t } from "../lib/i18n";', 'import { t } from "../lib/i18n";\nimport { withWidth } from "../lib/with-width";')
s = s.replace('src={product.imageUrl}', 'src={withWidth(product.imageUrl)}')
c.write_text(s)

g = pathlib.Path("app/components/gallery.tsx"); s = g.read_text()
s = s.replace('type Photo', 'import { withWidth } from "../lib/with-width";\n\ntype Photo')
s = s.replace('function tileStyle(url: string | null) {\n  return { backgroundImage: `url("${url ?? ""}"), url("${FALLBACK}")` };',
              'function tileStyle(url: string | null, small = false) {\n  const src = small ? withWidth(url) : url;\n  return { backgroundImage: `url("${src ?? ""}"), url("${FALLBACK}")` };')
s = s.replace('style={tileStyle(p.url)}', 'style={tileStyle(p.url, true)}')
s = s.replace('<div className="main-tile" style={tileStyle(lead?.url ?? null)} />',
              '<div className="main-tile" style={tileStyle(lead?.url ?? null)} />\n      {lead?.caption ? <p className="caption" dangerouslySetInnerHTML={{ __html: lead.caption }} /> : null}')
s = s.replace('src={p.url ?? FALLBACK}', 'src={withWidth(p.url) ?? FALLBACK}')
g.write_text(s)

t = pathlib.Path("app/components/gallery.test.tsx"); s = t.read_text().rstrip()
assert s.endswith("});")
s = s[:-3] + '''
  it("adds ?w=800 to sub tiles only", () => {
    const { container } = render(<Gallery photos={photos} />);
    const main = container.querySelector(".main-tile") as HTMLElement;
    const sub = container.querySelector(".sub-tile") as HTMLElement;
    expect(main.style.backgroundImage).toContain('url("/img/a.jpg")');
    expect(sub.style.backgroundImage).toContain('url("/img/b.jpg?w=800")');
  });

  it("adds ?w=800 to thumbnails", () => {
    const { container } = render(<Gallery photos={photos} />);
    const srcs = Array.from(container.querySelectorAll(".thumbs img")).map((i) => i.getAttribute("src"));
    expect(srcs).toEqual(["/img/a.jpg?w=800", "/img/b.jpg?w=800", "/img/c.jpg?w=800"]);
  });
});
'''
t.write_text(s)
PY
export GIT_AUTHOR_DATE="2026-01-03T00:00:00Z" GIT_COMMITTER_DATE="2026-01-03T00:00:00Z"
git commit -q -am "the change: add ?w=800 to small images"
