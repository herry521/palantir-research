#!/usr/bin/env bash
set -euo pipefail

ROOT="deliverables"
required_files=(
  "$ROOT/index.html"
  "$ROOT/styles.css"
  "$ROOT/app.js"
  "$ROOT/pages/overview.html"
  "$ROOT/pages/data-engineering-platform-map.html"
  "$ROOT/pages/pro-code-capability.html"
  "$ROOT/pages/expression-and-operators.html"
  "$ROOT/pages/execution-and-incremental.html"
  "$ROOT/pages/streaming-architecture.html"
  "$ROOT/pages/lineage-ontology-governance.html"
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
check_contains "$ROOT/pages/overview.html" "技术总览"
check_contains "$ROOT/pages/overview.html" "map-layers"
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
check_contains "$ROOT/pages/pro-code-capability.html" "高码能力研究"
check_contains "$ROOT/pages/pro-code-capability.html" "【实时】"
check_contains "$ROOT/pages/pro-code-capability.html" "【推断】"
check_contains "$ROOT/pages/pro-code-capability.html" "【猜测】"
check_contains "$ROOT/pages/expression-and-operators.html" "表达层"
check_contains "$ROOT/pages/execution-and-incremental.html" "增量"
check_contains "$ROOT/pages/streaming-architecture.html" "流式"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "Ontology"
check_contains "$ROOT/pages/engineering-and-ecosystem.html" "工程化"
check_contains "$ROOT/styles.css" ".split-stack"
check_contains "$ROOT/pages/expression-and-operators.html" "split-stack"
check_contains "$ROOT/pages/execution-and-incremental.html" "split-stack"
check_contains "$ROOT/pages/streaming-architecture.html" "split-stack"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "split-stack"
check_contains "$ROOT/styles.css" ".mechanism-grid"
check_contains "$ROOT/styles.css" ".mechanism-card"
check_contains "$ROOT/styles.css" ".map-layers"
check_contains "$ROOT/pages/engineering-and-ecosystem.html" "detail-grid mechanism-grid"
check_contains "$ROOT/pages/expression-and-operators.html" "mechanism-card"
check_contains "$ROOT/pages/execution-and-incremental.html" "mechanism-card"
check_contains "$ROOT/pages/streaming-architecture.html" "mechanism-card"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "mechanism-card"
check_contains "$ROOT/pages/engineering-and-ecosystem.html" "mechanism-card"

grep -q 'href="pages/overview.html"' "$ROOT/index.html" || {
  echo "Homepage must link to overview page"
  exit 1
}

grep -q 'href="pages/data-engineering-platform-map.html"' "$ROOT/index.html" || {
  echo "Homepage must link to capability map page"
  exit 1
}

grep -q 'href="pages/pro-code-capability.html"' "$ROOT/index.html" || {
  echo "Homepage must link to pro-code capability page"
  exit 1
}

echo "Summary site verification passed."
