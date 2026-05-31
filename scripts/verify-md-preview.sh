#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-deliverables}"
NODE_BIN="${NODE_BIN:-/Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node}"
NODE_MODULES="${NODE_MODULES:-/Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules}"

[[ -f "$ROOT/pages/md-preview.html" ]] || { echo "Missing file: $ROOT/pages/md-preview.html"; exit 1; }
[[ -f "$ROOT/md-docs.js" ]] || { echo "Missing file: $ROOT/md-docs.js"; exit 1; }
[[ -f "$ROOT/app.js" ]] || { echo "Missing file: $ROOT/app.js"; exit 1; }

grep -q "window.PALANTIR_MD_DOCS" "$ROOT/md-docs.js" || { echo "Missing Markdown bundle global"; exit 1; }
grep -q "docs/library/02-data-engineering-core.md" "$ROOT/md-docs.js" || { echo "Markdown bundle missing library chapter"; exit 1; }
grep -q "rewriteMarkdownLinks" "$ROOT/app.js" || { echo "Missing Markdown link rewrite function"; exit 1; }
grep -q "md-preview.html?doc=" "$ROOT/app.js" || { echo "Missing Markdown preview link target"; exit 1; }
grep -q "data-md-preview-doc" "$ROOT/pages/md-preview.html" || { echo "Missing Markdown preview mount"; exit 1; }

if [[ ! -x "$NODE_BIN" ]]; then
  NODE_BIN="$(command -v node)"
fi

if [[ ! -d "$NODE_MODULES" ]]; then
  echo "Missing Playwright node_modules: $NODE_MODULES"
  echo "Set NODE_MODULES to a directory that contains the playwright package."
  exit 1
fi

export NODE_PATH="$NODE_MODULES${NODE_PATH:+:$NODE_PATH}"
export ROOT

"$NODE_BIN" <<'NODE'
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { chromium } = require("playwright");

const root = path.resolve(process.env.ROOT || "deliverables");

async function main() {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    const previewUrl = pathToFileURL(path.join(root, "pages/md-preview.html")).href + "?doc=docs/library/02-data-engineering-core.md";
    await page.goto(previewUrl, { waitUntil: "networkidle" });

    const title = await page.title();
    if (title !== "Data Engineering Core - Markdown 文档预览") {
      throw new Error(`Unexpected preview title: ${title}`);
    }

    const bodyText = await page.locator("body").innerText();
    for (const text of ["Markdown 文档预览", "docs/library/02-data-engineering-core.md", "Data Engineering Core", "摘要与洞察", "核心链路"]) {
      if (!bodyText.includes(text)) {
        throw new Error(`Markdown preview missing text: ${text}`);
      }
    }

    const renderedCounts = await page.evaluate(() => ({
      headings: document.querySelectorAll(".markdown-body h1, .markdown-body h2").length,
      tables: document.querySelectorAll(".markdown-body table").length,
      codeBlocks: document.querySelectorAll(".markdown-body pre code").length,
      links: document.querySelectorAll(".markdown-body a[href*='md-preview.html?doc=']").length,
    }));

    if (renderedCounts.headings < 2 || renderedCounts.tables < 1 || renderedCounts.codeBlocks < 1 || renderedCounts.links < 1) {
      throw new Error(`Markdown renderer did not produce expected structures: ${JSON.stringify(renderedCounts)}`);
    }

    const bookPage = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    await bookPage.goto(pathToFileURL(path.join(root, "pages/book-library.html")).href, { waitUntil: "networkidle" });
    const href = await bookPage.locator("a", { hasText: "docs/topics/pipeline.md" }).first().getAttribute("href");
    if (!href || !href.includes("md-preview.html?doc=") || !href.includes("docs%2Ftopics%2Fpipeline.md")) {
      throw new Error(`Markdown source link was not rewritten to preview URL: ${href}`);
    }
  } finally {
    await browser.close();
  }
}

main()
  .then(() => console.log("Markdown preview verification passed."))
  .catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
NODE
