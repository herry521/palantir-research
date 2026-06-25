#!/usr/bin/env bash
set -euo pipefail

ROOT="deliverables"
required_files=(
  "$ROOT/index.html"
  "$ROOT/styles.css"
  "$ROOT/app.js"
  "$ROOT/md-docs.js"
  "$ROOT/pages/book-library.html"
  "$ROOT/pages/md-preview.html"
  "$ROOT/pages/overview.html"
  "$ROOT/pages/data-engineering-platform-map.html"
  "$ROOT/pages/pipeline-builder-operators-overview.html"
  "$ROOT/pages/pro-code-capability.html"
  "$ROOT/pages/expression-and-operators.html"
  "$ROOT/pages/execution-and-incremental.html"
  "$ROOT/pages/foundry-schedule-module.html"
  "$ROOT/pages/streaming-architecture.html"
  "$ROOT/pages/lineage-ontology-governance.html"
  "$ROOT/pages/dataset-permission-marking.html"
  "$ROOT/pages/data-quality.html"
  "$ROOT/pages/data-integration-capability-map.html"
  "$ROOT/pages/data-integration-permission-system.html"
  "$ROOT/pages/engineering-and-ecosystem.html"
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || { echo "Missing file: $file"; exit 1; }
done

check_contains() {
  local file="$1"
  local pattern="$2"
  grep -q "$pattern" "$file" || { echo "Missing pattern '$pattern' in $file"; exit 1; }
}

check_contains "$ROOT/index.html" "Palantir"
check_contains "$ROOT/index.html" "三个管理判断"
check_contains "$ROOT/index.html" "分层阅读入口"
check_contains "$ROOT/index.html" "专题下钻目录"
check_contains "$ROOT/index.html" "Book 式文档库"
check_contains "$ROOT/index.html" "Foundry Schedule 运行模式"
check_contains "$ROOT/index.html" "Data Integration 战情图"
check_contains "$ROOT/index.html" "Data Integration 权限控制面"
check_contains "$ROOT/index.html" "Data Quality 质量控制面"
check_contains "$ROOT/app.js" "rewriteMarkdownLinks"
check_contains "$ROOT/app.js" "md-preview.html?doc="
check_contains "$ROOT/app.js" "https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/blob/main/"
check_contains "$ROOT/md-docs.js" "window.PALANTIR_MD_DOCS"
check_contains "$ROOT/pages/book-library.html" "Book 式文档体系预览"
check_contains "$ROOT/pages/book-library.html" "结论预览"
check_contains "$ROOT/pages/book-library.html" "相关调研文档"
check_contains "$ROOT/pages/book-library.html" "docs/library/SUMMARY.md"
check_contains "$ROOT/pages/book-library.html" "docs/topics/pipeline.md"
check_contains "$ROOT/pages/book-library.html" "Data Quality 质量控制面"
check_contains "$ROOT/pages/book-library.html" "docs/synthesis/palantir-data-quality-module-research.md"
check_contains "$ROOT/pages/book-library.html" "docs/synthesis/data-integration-permission-system-roadmap.md"
check_contains "$ROOT/pages/md-preview.html" "Markdown 文档预览"
check_contains "$ROOT/pages/md-preview.html" "data-md-preview-doc"
check_contains "$ROOT/pages/md-preview.html" "../md-docs.js"
check_contains "$ROOT/pages/md-preview.html" "在 GitLab EE 打开原始 Markdown"
check_contains "$ROOT/pages/overview.html" "技术总览"
check_contains "$ROOT/pages/overview.html" "map-layers"
check_contains "$ROOT/pages/overview.html" "Book 式文档体系预览"
check_contains "$ROOT/pages/overview.html" "专题 00"
check_contains "$ROOT/pages/overview.html" "专题 08"
check_contains "$ROOT/pages/overview.html" "专题 09"
check_contains "$ROOT/pages/overview.html" "Foundry Schedule 运行模式"
check_contains "$ROOT/pages/overview.html" "Data Integration 权限控制面"
check_contains "$ROOT/pages/overview.html" "Data Quality 质量控制面"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "能力建设关注点"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "Dataset 版本模型"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "Ontology / Writeback"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "capability-layer"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "数据同步与 Pipeline 专项关注"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "Connector 插件模型"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "Dataset Control Plane"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "ReadSession / WriteSession"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "Faster / 轻量执行引擎规划"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "Engine Router"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "Spark fallback"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "DataFusion"
check_contains "$ROOT/pages/data-engineering-platform-map.html" "Media Set 资产模型"
check_contains "$ROOT/pages/pipeline-builder-operators-overview.html" "Pipeline Builder 算子总览"
check_contains "$ROOT/pages/pipeline-builder-operators-overview.html" "两条主线"
check_contains "$ROOT/pages/pro-code-capability.html" "高码能力研究"
check_contains "$ROOT/pages/pro-code-capability.html" "【事实 <a class=\"confidence-ref\""
check_contains "$ROOT/pages/pro-code-capability.html" "href=\"https://www.palantir.com/docs/foundry/code-repositories/overview/index.html\""
check_contains "$ROOT/pages/pro-code-capability.html" "href=\"https://www.palantir.com/docs/foundry/pipeline-builder/export-pipeline\""
check_contains "$ROOT/pages/pro-code-capability.html" "【推断】"
check_contains "$ROOT/pages/pro-code-capability.html" "【猜测】"
check_contains "$ROOT/pages/pro-code-capability.html" "运行时、计算引擎与依赖"
check_contains "$ROOT/pages/pro-code-capability.html" "质量、血缘、权限与可观测性"
check_contains "$ROOT/pages/pro-code-capability.html" "低码与高码互操作"
check_contains "$ROOT/pages/pro-code-capability.html" "建议验证路线"
check_contains "$ROOT/pages/pro-code-capability.html" "#7 docs/raw/23-code-repositories-engineering-entry.md"
check_contains "$ROOT/pages/pro-code-capability.html" "#14 docs/raw/28-pipeline-builder-pro-code-interop.md"
check_contains "$ROOT/pages/expression-and-operators.html" "表达层"
check_contains "$ROOT/pages/execution-and-incremental.html" "增量"
check_contains "$ROOT/pages/foundry-schedule-module.html" "Foundry Schedule 运行模式"
check_contains "$ROOT/pages/foundry-schedule-module.html" "Trigger 是状态机"
check_contains "$ROOT/pages/foundry-schedule-module.html" "Schedule 到 Build 的运行链路"
check_contains "$ROOT/pages/foundry-schedule-module.html" "四个实际案例"
check_contains "$ROOT/pages/foundry-schedule-module.html" "OR 事件"
check_contains "$ROOT/pages/foundry-schedule-module.html" "AND satisfied"
check_contains "$ROOT/pages/foundry-schedule-module.html" "术语来源要分层"
check_contains "$ROOT/pages/foundry-schedule-module.html" "多条件组合的内部判定模型"
check_contains "$ROOT/pages/foundry-schedule-module.html" "trigger_tree + observed_events"
check_contains "$ROOT/pages/foundry-schedule-module.html" "官方证据：布尔树"
check_contains "$ROOT/pages/foundry-schedule-module.html" "Palantir Linter rules"
check_contains "$ROOT/pages/foundry-schedule-module.html" "Build、staleness 与 force build"
check_contains "$ROOT/pages/foundry-schedule-module.html" "拆开业务周期调度与 freshness 调度"
check_contains "$ROOT/pages/foundry-schedule-module.html" "docs/synthesis/foundry-schedule-module-deep-dive.md"
check_contains "$ROOT/pages/streaming-architecture.html" "流式"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "Ontology"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "血缘关系图"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "自建 Dataset 血缘建设方案"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "docs/raw/29-lineage-branch-version-pipeline-sync.md"
check_contains "$ROOT/pages/dataset-permission-marking.html" "Dataset 权限与 Marking 架构"
check_contains "$ROOT/pages/dataset-permission-marking.html" "Dataset 权限全景"
check_contains "$ROOT/pages/dataset-permission-marking.html" "Marking 的设计和传播"
check_contains "$ROOT/pages/dataset-permission-marking.html" "端到端实现链路"
check_contains "$ROOT/pages/dataset-permission-marking.html" "Marking 传递与计算设计"
check_contains "$ROOT/pages/dataset-permission-marking.html" "carried_requirements"
check_contains "$ROOT/pages/dataset-permission-marking.html" "不等于都被 direct marking"
check_contains "$ROOT/pages/dataset-permission-marking.html" "docs/synthesis/dataset-permission-marking-architecture-summary.md"
check_contains "$ROOT/pages/data-quality.html" "Data Quality 质量控制面"
check_contains "$ROOT/pages/data-quality.html" "核心结论"
check_contains "$ROOT/pages/data-quality.html" "Data Expectations"
check_contains "$ROOT/pages/data-quality.html" "Health Checks"
check_contains "$ROOT/pages/data-quality.html" "Monitoring Views"
check_contains "$ROOT/pages/data-quality.html" "BuildCheckResult"
check_contains "$ROOT/pages/data-quality.html" "ExternalRoutePolicy"
check_contains "$ROOT/pages/data-quality.html" "docs/synthesis/palantir-data-quality-module-research.md"
check_contains "$ROOT/pages/data-quality.html" "docs/raw/49-data-quality-external-notification-security.md"
check_contains "$ROOT/pages/data-integration-capability-map.html" "Data Integration 战情图"
check_contains "$ROOT/pages/data-integration-capability-map.html" "di-capability-map"
check_contains "$ROOT/pages/data-integration-permission-system.html" "Data Integration 权限控制面"
check_contains "$ROOT/pages/data-integration-permission-system.html" "权限控制面覆盖链路"
check_contains "$ROOT/pages/data-integration-permission-system.html" "P0 / P1 / P2 建设路线"
check_contains "$ROOT/pages/data-integration-permission-system.html" "运行时身份与外发边界"
check_contains "$ROOT/pages/data-integration-permission-system.html" "专家评审共识"
check_contains "$ROOT/pages/data-integration-permission-system.html" "docs/synthesis/data-integration-permission-system-roadmap.md"
check_contains "$ROOT/styles.css" ".permission-matrix"
check_contains "$ROOT/styles.css" ".access-equation"
check_contains "$ROOT/styles.css" ".architecture-chain"
check_contains "$ROOT/styles.css" ".implementation-chain"
check_contains "$ROOT/styles.css" ".calculation-flow"
check_contains "$ROOT/styles.css" ".formula-panel"
check_contains "$ROOT/pages/engineering-and-ecosystem.html" "工程化"
check_contains "$ROOT/pages/engineering-and-ecosystem.html" "Media Set 如何把非结构化数据纳入平台"
check_contains "$ROOT/pages/engineering-and-ecosystem.html" "docs/raw/31-media-set-implementation-deep-dive.md"
check_contains "$ROOT/styles.css" ".split-stack"
check_contains "$ROOT/pages/expression-and-operators.html" "split-stack"
check_contains "$ROOT/pages/execution-and-incremental.html" "split-stack"
check_contains "$ROOT/pages/streaming-architecture.html" "split-stack"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "split-stack"
check_contains "$ROOT/styles.css" ".mechanism-grid"
check_contains "$ROOT/styles.css" ".mechanism-card"
check_contains "$ROOT/styles.css" ".lineage-map-panel"
check_contains "$ROOT/styles.css" ".lineage-flow"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "dataset-lineage-build"
check_contains "$ROOT/styles.css" ".map-layers"
check_contains "$ROOT/pages/engineering-and-ecosystem.html" "detail-grid mechanism-grid"
check_contains "$ROOT/pages/expression-and-operators.html" "mechanism-card"
check_contains "$ROOT/pages/execution-and-incremental.html" "mechanism-card"
check_contains "$ROOT/pages/streaming-architecture.html" "mechanism-card"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "mechanism-card"
check_contains "$ROOT/pages/engineering-and-ecosystem.html" "mechanism-card"

for file in "${required_files[@]}"; do
  if [[ "$file" == "$ROOT/styles.css" || "$file" == "$ROOT/app.js" || "$file" == "$ROOT/md-docs.js" ]]; then
    continue
  fi

  if [[ "$file" == "$ROOT/pages/pipeline-builder-operators-overview.html" ]]; then
    continue
  fi

  nav_count="$(grep -o 'data-nav href=' "$file" | wc -l | tr -d ' ')"
  [[ "$nav_count" == "5" ]] || {
    echo "Expected 5 primary nav links in $file, found $nav_count"
    exit 1
  }

  if [[ "$file" != "$ROOT/pages/data-integration-capability-map.html" ]]; then
    check_contains "$file" "Palantir Foundry / Pipeline 调研材料库"
    check_contains "$file" "统一入口：首页 / 总览 / 蓝图 / 手册 / 文档"
  fi
done

grep -q 'href="pages/overview.html"' "$ROOT/index.html" || {
  echo "Homepage must link to overview page"
  exit 1
}

grep -q 'href="pages/book-library.html"' "$ROOT/index.html" || {
  echo "Homepage must link to book library preview page"
  exit 1
}

grep -q 'href="book-library.html"' "$ROOT/pages/overview.html" || {
  echo "Overview page must link to book library preview page"
  exit 1
}

grep -q 'href="pages/data-engineering-platform-map.html"' "$ROOT/index.html" || {
  echo "Homepage must link to capability map page"
  exit 1
}

grep -q 'href="pages/pipeline-builder-operators-overview.html"' "$ROOT/index.html" || {
  echo "Homepage must link to Pipeline Builder operators overview page"
  exit 1
}

grep -q 'href="pages/pro-code-capability.html"' "$ROOT/index.html" || {
  echo "Homepage must link to pro-code capability page"
  exit 1
}

grep -q 'href="pages/dataset-permission-marking.html"' "$ROOT/index.html" || {
  echo "Homepage must link to dataset permission marking page"
  exit 1
}

grep -q 'href="pages/foundry-schedule-module.html"' "$ROOT/index.html" || {
  echo "Homepage must link to Foundry schedule module page"
  exit 1
}

grep -q 'href="pages/data-integration-permission-system.html"' "$ROOT/index.html" || {
  echo "Homepage must link to Data Integration permission page"
  exit 1
}

grep -q 'href="pages/data-integration-capability-map.html"' "$ROOT/index.html" || {
  echo "Homepage must link to Data Integration capability map page"
  exit 1
}

grep -q 'href="pages/data-quality.html"' "$ROOT/index.html" || {
  echo "Homepage must link to Data Quality page"
  exit 1
}

echo "Summary site verification passed."
