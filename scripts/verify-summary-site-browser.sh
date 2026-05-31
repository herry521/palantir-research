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
    requiredText: ["三个管理判断", "Book 式文档体系预览", "高码能力研究", "Pipeline Builder 算子总览", "Dataset 权限与 Marking 架构", "Data Integration 权限控制面", "Data Quality 质量控制面", "十个专题页", "Media Set", "Foundry Schedule 运行模式"],
  },
  {
    path: "pages/book-library.html",
    slug: "book-library",
    title: "Book 式文档体系预览",
    requiredText: ["Book 式文档体系预览", "章节导读", "结论预览", "相关调研文档", "Data Quality 质量控制面", "docs/library/SUMMARY.md", "docs/topics/pipeline.md", "docs/synthesis/palantir-data-quality-module-research.md", "docs/synthesis/data-integration-permission-system-roadmap.md"],
    rewrittenMarkdownLinks: [
      { text: "docs/topics/pipeline.md", doc: "docs/topics/pipeline.md" },
      { text: "docs/library/SUMMARY.md", doc: "docs/library/SUMMARY.md" },
    ],
  },
  {
    path: "pages/md-preview.html",
    query: "?doc=docs/library/00-executive-summary.md",
    slug: "md-preview",
    title: "Executive Summary - Markdown 文档预览",
    requiredText: ["Markdown 文档预览", "docs/library/00-executive-summary.md", "Executive Summary", "摘要与洞察", "平台壁垒"],
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
    requiredText: ["完整阅读路径", "Book 式文档体系预览", "高码能力研究", "能力建设关注点", "Dataset 权限与 Marking 架构", "Data Integration 权限控制面", "Data Quality 质量控制面", "Media Set 资产模型", "Foundry Schedule 运行模式", "算子主线如何嵌入平台图", "Pipeline Builder 算子总览页"],
    iframeSelector: 'iframe[title="Pipeline Builder 算子总览页预览"]',
    iframeRequiredText: ["算子总览", "transform 清单", "expression 清单"],
    iframeSrc: "pipeline-builder-operators-overview.html",
  },
  {
    path: "pages/pipeline-builder-operators-overview.html",
    slug: "pipeline-builder-operators-overview",
    title: "Pipeline Builder 算子总览",
    requiredText: ["一页总结", "Transform 主线", "Expression 主线", "证据边界"],
  },
  {
    path: "pages/data-engineering-platform-map.html",
    slug: "data-engineering-platform-map",
    title: "数据工程能力建设蓝图",
    requiredText: ["能力建设关注点", "Dataset Control Plane", "Media Set 资产模型", "Engine Router", "算子注册中心"],
  },
  {
    path: "pages/expression-and-operators.html",
    slug: "expression-and-operators",
    title: "表达层与算子平台",
    requiredText: ["表达层", "Transform DSL", "89 条 transform", "335 条 expression", "Pipeline Builder 算子总览"],
  },
  {
    path: "pages/execution-and-incremental.html",
    slug: "execution-and-incremental",
    title: "执行引擎与增量链路",
    requiredText: ["执行引擎", "增量", "Transaction"],
  },
  {
    path: "pages/foundry-schedule-module.html",
    slug: "foundry-schedule-module",
    title: "Foundry Schedule 运行模式",
    requiredText: ["Foundry Schedule 运行模式", "Schedule 到 Build 的运行链路", "Trigger 是状态机", "多条件组合的内部判定模型", "trigger_tree + observed_events", "官方证据：布尔树", "Palantir Linter rules", "四个实际案例", "AND satisfied", "术语来源要分层", "Build、staleness 与 force build", "拆开业务周期调度与 freshness 调度"],
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
    path: "pages/dataset-permission-marking.html",
    slug: "dataset-permission-marking",
    title: "Dataset 权限与 Marking 架构",
    requiredText: ["Dataset 权限与 Marking 架构", "Dataset 权限全景", "访问判定模型", "Marking 的设计和传播", "端到端实现链路", "Marking 传递与计算设计", "不等于都被 direct marking"],
  },
  {
    path: "pages/data-quality.html",
    slug: "data-quality",
    title: "Data Quality 质量控制面",
    requiredText: ["Data Quality 质量控制面", "核心结论", "Data Expectations", "Health Checks", "Monitoring Views", "BuildCheckResult", "ExternalRoutePolicy", "docs/synthesis/palantir-data-quality-module-research.md", "docs/raw/49-data-quality-external-notification-security.md"],
  },
  {
    path: "pages/data-integration-permission-system.html",
    slug: "data-integration-permission-system",
    title: "Data Integration 权限控制面",
    requiredText: ["Data Integration 权限控制面", "核心结论", "权限控制面覆盖链路", "P0 / P1 / P2 建设路线", "运行时身份与外发边界", "专家评审共识", "docs/synthesis/data-integration-permission-system-roadmap.md"],
  },
  {
    path: "pages/engineering-and-ecosystem.html",
    slug: "engineering-and-ecosystem",
    title: "工程化与生态边界",
    requiredText: ["工程化", "测试", "生态", "Media Set 如何把非结构化数据纳入平台"],
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

  const fileUrl = pathToFileURL(path.join(root, pageSpec.path)).href + (pageSpec.query || "");
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

  for (const linkSpec of pageSpec.rewrittenMarkdownLinks || []) {
    const link = page.locator("a", { hasText: linkSpec.text }).first();
    const href = await link.getAttribute("href");
    const expectedDoc = encodeURIComponent(linkSpec.doc);
    if (!href || !href.includes("md-preview.html?doc=") || !href.includes(expectedDoc)) {
      throw new Error(`${pageSpec.path}: Markdown link "${linkSpec.text}" was not rewritten to preview page, got "${href}"`);
    }
  }

  if (pageSpec.iframeSelector) {
    const frame = page.frameLocator(pageSpec.iframeSelector);
    await frame.locator("body").waitFor({ state: "visible", timeout: 5000 });
    const frameText = await frame.locator("body").innerText({ timeout: 5000 });
    for (const text of pageSpec.iframeRequiredText || []) {
      if (!frameText.includes(text)) {
        throw new Error(`${pageSpec.path}: embedded iframe missing text "${text}"`);
      }
    }
  }

  const bodyBox = await page.locator("body").boundingBox();
  if (!bodyBox || bodyBox.width < 320 || bodyBox.height < 200) {
    throw new Error(`${pageSpec.path}: body did not render with a usable size`);
  }

  const horizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  if (horizontalOverflow > 2) {
    throw new Error(`${pageSpec.path}: page overflows horizontally by ${horizontalOverflow}px`);
  }

  if (viewport.name === "desktop" && (await page.locator(".site-nav .nav-links a").count()) > 0) {
    const navTopSpread = await page.locator(".site-nav .nav-links a").evaluateAll((items) => {
      const tops = items.map((item) => Math.round(item.getBoundingClientRect().top));
      return Math.max(...tops) - Math.min(...tops);
    });
    if (navTopSpread > 8) {
      throw new Error(`${pageSpec.path}: desktop primary navigation appears to wrap; top spread is ${navTopSpread}px`);
    }
  }

  if (errors.length > 0) {
    throw new Error(`${pageSpec.path}: browser console errors: ${errors.join(" | ")}`);
  }

  const screenshot = await page.screenshot({ fullPage: true });
  const screenshotName = `${pageSpec.slug}-${viewport.name}.png`;
  const screenshotPath = path.join(screenshotDir, screenshotName);
  fs.writeFileSync(screenshotPath, screenshot);
  assertScreenshotLooksRendered(screenshot, `${pageSpec.path} ${viewport.name}`);

  if (pageSpec.iframeSelector) {
    const iframeElement = page.locator(pageSpec.iframeSelector);
    await iframeElement.scrollIntoViewIfNeeded();
    const iframeElementScreenshot = await iframeElement.screenshot();
    const iframeElementScreenshotName = `${pageSpec.slug}-${viewport.name}-iframe-element.png`;
    const iframeElementScreenshotPath = path.join(screenshotDir, iframeElementScreenshotName);
    fs.writeFileSync(iframeElementScreenshotPath, iframeElementScreenshot);
    assertScreenshotLooksRendered(iframeElementScreenshot, `${pageSpec.path} ${viewport.name} embedded iframe element`);
    console.log(`Captured ${viewport.name} iframe element screenshot: ${iframeElementScreenshotPath}`);

    const iframePage = await browser.newPage({ viewport });
    const iframeUrl = new URL(pageSpec.iframeSrc, fileUrl).href;
    await iframePage.goto(iframeUrl, { waitUntil: "networkidle" });
    await iframePage.locator("body").waitFor({ state: "visible", timeout: 5000 });
    const iframeScreenshot = await iframePage.screenshot({ fullPage: false });
    const iframeScreenshotName = `${pageSpec.slug}-${viewport.name}-iframe.png`;
    const iframeScreenshotPath = path.join(screenshotDir, iframeScreenshotName);
    fs.writeFileSync(iframeScreenshotPath, iframeScreenshot);
    assertScreenshotLooksRendered(iframeScreenshot, `${pageSpec.path} ${viewport.name} embedded iframe`);
    console.log(`Captured ${viewport.name} iframe screenshot: ${iframeScreenshotPath}`);
    await iframePage.close();
  }

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
