#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-deliverables}"
NODE_BIN="${NODE_BIN:-/Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node}"
NODE_MODULES="${NODE_MODULES:-/Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules}"

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
const pages = [
  {
    path: "index.html",
    title: "Palantir 调研总结一页纸",
    requiredText: ["三个管理判断", "高码能力研究"],
  },
  {
    path: "pages/pro-code-capability.html",
    title: "高码能力研究",
    requiredText: ["Palantir 高码能力研究", "【实时】", "【推断】", "【猜测】"],
  },
];

async function checkPage(browser, pageSpec, viewport) {
  const page = await browser.newPage({ viewport });
  const errors = [];
  page.on("console", (message) => {
    if (message.type() === "error") {
      errors.push(message.text());
    }
  });
  page.on("pageerror", (error) => errors.push(error.message));

  const fileUrl = pathToFileURL(path.join(root, pageSpec.path)).href;
  await page.goto(fileUrl, { waitUntil: "networkidle" });

  const title = await page.title();
  if (title !== pageSpec.title) {
    throw new Error(`${pageSpec.path}: expected title "${pageSpec.title}", got "${title}"`);
  }

  const bodyText = await page.locator("body").innerText();
  for (const text of pageSpec.requiredText) {
    if (!bodyText.includes(text)) {
      throw new Error(`${pageSpec.path}: missing text "${text}"`);
    }
  }

  const bodyBox = await page.locator("body").boundingBox();
  if (!bodyBox || bodyBox.width < 320 || bodyBox.height < 200) {
    throw new Error(`${pageSpec.path}: body did not render with a usable size`);
  }

  if (errors.length > 0) {
    throw new Error(`${pageSpec.path}: browser console errors: ${errors.join(" | ")}`);
  }

  await page.close();
}

(async () => {
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (error) {
    throw new Error(
      `Unable to launch Playwright Chromium. In Codex sandboxed shells, rerun this script with escalated permissions. Original error: ${error.message}`,
    );
  }

  try {
    for (const pageSpec of pages) {
      await checkPage(browser, pageSpec, { width: 1440, height: 1100 });
      await checkPage(browser, pageSpec, { width: 390, height: 900 });
    }
  } finally {
    await browser.close();
  }

  console.log("Summary site browser verification passed.");
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
NODE
