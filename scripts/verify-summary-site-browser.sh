#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-deliverables}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-/tmp/palantir-summary-site-screenshots}"
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
export SCREENSHOT_DIR

"$NODE_BIN" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { PNG } = require("pngjs");
const { chromium } = require("playwright");

const root = path.resolve(process.env.ROOT || "deliverables");
const screenshotDir = path.resolve(process.env.SCREENSHOT_DIR || "/tmp/palantir-summary-site-screenshots");
const pages = [
  {
    path: "index.html",
    slug: "home",
    title: "Palantir 调研总结一页纸",
    requiredText: ["三个管理判断", "高码能力研究"],
  },
  {
    path: "pages/pro-code-capability.html",
    slug: "pro-code-capability",
    title: "高码能力研究",
    requiredText: ["Palantir 高码能力研究", "【事实 ref】", "【推断】", "【猜测】"],
  },
  {
    path: "pages/overview.html",
    slug: "overview",
    title: "Palantir 研发技术总览",
    requiredText: ["完整阅读路径", "高码能力研究", "能力建设关注点"],
  },
  {
    path: "pages/data-engineering-platform-map.html",
    slug: "data-engineering-platform-map",
    title: "数据工程能力建设蓝图",
    requiredText: ["能力建设关注点", "Dataset Control Plane", "Engine Router"],
  },
  {
    path: "pages/expression-and-operators.html",
    slug: "expression-and-operators",
    title: "表达层与算子平台",
    requiredText: ["表达层", "Transform DSL", "算子"],
  },
  {
    path: "pages/execution-and-incremental.html",
    slug: "execution-and-incremental",
    title: "执行引擎与增量链路",
    requiredText: ["执行引擎", "增量", "Transaction"],
  },
  {
    path: "pages/streaming-architecture.html",
    slug: "streaming-architecture",
    title: "流式架构",
    requiredText: ["流式架构", "Flink", "Streaming"],
  },
  {
    path: "pages/lineage-ontology-governance.html",
    slug: "lineage-ontology-governance",
    title: "血缘、Ontology 与治理",
    requiredText: ["Ontology", "Lineage", "治理"],
  },
  {
    path: "pages/engineering-and-ecosystem.html",
    slug: "engineering-and-ecosystem",
    title: "工程化与生态边界",
    requiredText: ["工程化", "测试", "生态"],
  },
];
const viewports = [
  { name: "desktop", width: 1440, height: 1100 },
  { name: "mobile", width: 390, height: 900 },
];

function assertScreenshotLooksRendered(buffer, label) {
  const png = PNG.sync.read(buffer);
  if (png.width < 320 || png.height < 200) {
    throw new Error(`${label}: screenshot dimensions are too small: ${png.width}x${png.height}`);
  }

  let visiblePixels = 0;
  const colors = new Set();
  const step = Math.max(1, Math.floor((png.width * png.height) / 8000));

  for (let pixel = 0; pixel < png.width * png.height; pixel += step) {
    const offset = pixel * 4;
    const alpha = png.data[offset + 3];
    if (alpha === 0) {
      continue;
    }
    visiblePixels += 1;
    const red = png.data[offset];
    const green = png.data[offset + 1];
    const blue = png.data[offset + 2];
    colors.add(`${red >> 4},${green >> 4},${blue >> 4}`);
  }

  if (visiblePixels < 1000 || colors.size < 12) {
    throw new Error(`${label}: screenshot appears blank or visually under-rendered`);
  }
}

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

  const screenshot = await page.screenshot({ fullPage: true });
  const screenshotName = `${pageSpec.slug}-${viewport.name}.png`;
  const screenshotPath = path.join(screenshotDir, screenshotName);
  fs.writeFileSync(screenshotPath, screenshot);
  assertScreenshotLooksRendered(screenshot, `${pageSpec.path} ${viewport.name}`);

  await page.close();
  return screenshotPath;
}

(async () => {
  fs.mkdirSync(screenshotDir, { recursive: true });

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
      for (const viewport of viewports) {
        const screenshotPath = await checkPage(browser, pageSpec, viewport);
        console.log(`Captured ${viewport.name} screenshot: ${screenshotPath}`);
      }
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
