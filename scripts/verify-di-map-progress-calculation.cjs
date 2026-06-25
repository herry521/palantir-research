const fs = require("fs");
const path = require("path");
const vm = require("vm");

const projectRoot = path.resolve(__dirname, "..");
const pageFiles = [
  "deliverables/pages/data-integration-capability-map.html",
  "deliverables/pages/data-integration-capability-map-b2.html",
  "deliverables/pages/data-integration-capability-map-b3.html"
];

function extractInlineScript(filePath) {
  const html = fs.readFileSync(filePath, "utf8");
  const match = html.match(/<script>([\s\S]*?)<\/script>/);
  if (!match) {
    throw new Error(`No inline script found in ${filePath}`);
  }
  return match[1];
}

function createSandbox() {
  return {
    Blob: function Blob() {},
    URL: {
      createObjectURL: () => "blob:test",
      revokeObjectURL: () => {}
    },
    alert: () => {},
    confirm: () => true,
    console,
    document: {
      addEventListener: () => {},
      body: {
        classList: {
          toggle: () => {}
        }
      },
      createElement: () => ({
        click: () => {}
      }),
      getElementById: () => ({
        addEventListener: () => {},
        classList: {
          toggle: () => {}
        },
        innerHTML: "",
        textContent: ""
      }),
      querySelectorAll: () => []
    },
    localStorage: {
      getItem: () => null,
      removeItem: () => {},
      setItem: () => {}
    },
    navigator: {
      clipboard: {
        writeText: () => Promise.resolve()
      }
    },
    prompt: () => ""
  };
}

function loadCalculationContext(file) {
  const filePath = path.join(projectRoot, file);
  const context = vm.createContext(createSandbox());
  vm.runInContext(extractInlineScript(filePath), context, { filename: filePath });
  return context;
}

function assertEqual(actual, expected, message) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

for (const file of pageFiles) {
  const context = loadCalculationContext(file);
  const schedulesTwoDone = vm.runInContext(
    `
      diMapStatuses = {
        [diStatusKey("schedules", "schedule")]: "done",
        [diStatusKey("schedules", "time-trigger")]: "done"
      };
      const schedules = DI_MAP_MODULES.find((module) => module.id === "schedules");
      diModuleStats(schedules);
    `,
    context
  );

  assertEqual(schedulesTwoDone.total, 5, `${file} Schedules visible capability total`);
  assertEqual(schedulesTwoDone.done, 2, `${file} Schedules visible completed count`);
  assertEqual(schedulesTwoDone.progress, 40, `${file} Schedules progress should use visible capability total`);

  const schedulesNonCoreRisk = vm.runInContext(
    `
      diMapStatuses = {
        [diStatusKey("schedules", "trigger-composition")]: "risk"
      };
      diModuleStats(DI_MAP_MODULES.find((module) => module.id === "schedules"));
    `,
    context
  );

  assertEqual(schedulesNonCoreRisk.hasRisk, true, `${file} Schedules non-core visible risk should mark module at risk`);
}

console.log("di map progress calculation verification ok");
