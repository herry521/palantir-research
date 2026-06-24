const path = require("path");
const { chromium } = require("playwright");

const projectRoot = path.resolve(__dirname, "..");
const pageUrl = `file://${path.join(projectRoot, "deliverables/pages/data-integration-capability-map.html")}`;

const customConfig = {
  version: 1,
  modules: [
    {
      id: "custom-ingestion",
      zone: "main",
      name: "Custom Ingestion",
      zhName: "自定义接入",
      description: "通过 JSON 动态配置生成的能力模块。",
      capabilities: [
        {
          id: "custom-batch",
          name: "Custom batch",
          zhName: "自定义批同步",
          core: true,
          children: ["configured from JSON"]
        }
      ]
    }
  ]
};

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

  try {
    await page.goto(pageUrl);
    await page.waitForLoadState("networkidle");

    await page.locator("#di-import-config-json").waitFor({ timeout: 3000 });
    await page.locator("#di-export-config-json").waitFor({ timeout: 3000 });
    await page.locator("#di-reset-config").waitFor({ timeout: 3000 });

    page.once("dialog", async (dialog) => {
      if (dialog.type() !== "prompt") {
        throw new Error(`Expected prompt dialog, got ${dialog.type()}`);
      }
      await dialog.accept(JSON.stringify(customConfig));
    });
    await page.click("#di-import-config-json");
    await page.waitForSelector(".di-map-module h3:text('Custom Ingestion')");

    const storedConfig = await page.evaluate(() => localStorage.getItem("palantir-di-capability-map-config-v1"));
    if (!storedConfig || !storedConfig.includes("custom-ingestion")) {
      throw new Error("Imported module config was not persisted to localStorage.");
    }

    page.once("dialog", async (dialog) => {
      if (dialog.type() !== "confirm") {
        throw new Error(`Expected confirm dialog, got ${dialog.type()}`);
      }
      await dialog.accept();
    });
    await page.click("#di-reset-config");
    await page.waitForSelector(".di-map-module h3:text('Schedules')");

    const customModuleCount = await page.locator(".di-map-module h3:text('Custom Ingestion')").count();
    if (customModuleCount !== 0) {
      throw new Error("Custom module remained visible after resetting config.");
    }

    console.log("dynamic config verification ok");
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
