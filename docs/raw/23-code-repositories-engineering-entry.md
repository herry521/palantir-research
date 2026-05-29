# 23 - Palantir Code Repositories 与高码工程入口调研

## 背景

本文件对应 Issue #7：调研 Palantir Code Repositories 作为高码工程入口的能力边界。前置资料源来自 `docs/raw/22-pro-code-source-map.md` 中 #7 关联的 S01、S02、S03，并补充同一官方文档体系下的 Preview、Debug、Impact analysis、Branch settings、Unit tests、Linter 等页面。

核心问题不是“Foundry 是否能保存代码”，而是 Code Repositories 是否把 Git、代码评审、权限、运行前检查、数据预览、调试、升级和影响分析整合为平台内工程入口。【事实】

## 可信度规则

- 【事实】：来自 Palantir 官方文档页面的当前可访问内容，或对官方页面的直接摘要。
- 【推断】：由多个官方事实组合出的工程判断，但官方没有用同一句话完整表述。
- 【猜测】：资料不足时的合理假设，仅用于标注证据缺口，不能当成结论。

## 核心结论

1. Code Repositories 是 Foundry 内置的 Web IDE 和 Git 工程入口，支持通过 Web UI 执行常见 Git 任务，包括分支、提交和打 tag。【事实】
2. Code Repositories 不只是代码文件管理器；官方明确把 PR/code review、协作和可配置权限作为仓库能力的一部分。【事实】
3. 每类 repository 都带作者体验能力，包括 IntelliSense、code linting、error checking 和 help dialogs；因此 Palantir 的高码入口内建了编辑期反馈，而不是完全依赖外部 IDE 或外部 CI。【事实】
4. Transforms repository 支持数据转换逻辑开发，并带 preview/debug 能力；支持语言包括 Python、Java、SQL。【事实】
5. Repository types 至少覆盖 Transforms、Functions 和模型开发；Functions 支持低延迟业务逻辑、Ontology 访问、基于 Ontology 类型的 autocomplete，以及 authoring 阶段 preview。【事实】
6. Preview 可以在有限输入样本上运行 transform，生成样例输出，且不提交变更、不运行 checks、不物化 Foundry dataset；它用于缩短“改代码-触发 build-看结果”的反馈环。【事实】
7. Debugger 可在 Code Repositories 中设置断点、查看变量、dataframes、函数和库行为，但官方页面说明 debugger 仅适用于 Python。【事实】
8. 受保护分支只能通过 PR 修改，并可要求 `ci/foundry-publish` 成功、代码评审、特定 reviewer/group approval、无 rejection、安全审批等条件。【事实】
9. PR 页面内置影响分析：会提示受影响 dataset 是否 stale，并展示 PR 影响的 dataset；Python 使用 Transforms Level Logic Versioning 生成受影响列表，Java 根据 PR 修改的源文件判断直接影响 dataset。【事实】
10. Repository upgrades 由 Foundry 生成 upgrade PR，包含 Transforms template 更新和 runtime improvements；可自动合并，也会因覆盖用户改动、affected datasets 未用最新代码构建、Spark runtime module 变化等情况要求人工介入。【事实】
11. Code Repositories 的高码工程入口模型是“代码变更影响数据资产”的闭环，而普通 Git+CI 通常只天然理解源码、测试和 artifact，需要额外集成才能理解 dataset、marking/security、Spark runtime、project reference 和 data expectation 影响。【推断】
12. Linter 是旁路治理能力：它扫描 Foundry enrollment 的资源状态，给出成本、稳定性、韧性等建议，并可产生 fix proposal；这说明 Palantir 的工程治理不只发生在单个仓库 PR 内。【事实】

## 能力矩阵

| 能力 | Palantir 官方能力 | 可信度 | 关键证据 |
| --- | --- | --- | --- |
| Git | Web UI 支持 branching、committing、tagging releases 等常见 Git 任务。 | 【事实】 | Code Repositories Overview |
| PR/code review | 仓库集成 pull requests、code review、collaboration。 | 【事实】 | Code Repositories Overview |
| 权限与治理 | PR、保护分支、merge 权限、required reviewers、advanced approval policy、安全审批等进入分支策略。 | 【事实】 | Branch settings |
| Web IDE | 官方称 Code Repositories 提供 web-based IDE，用于在 Foundry 中写作和协作 production-ready code。 | 【事实】 | Code Repositories Overview |
| IntelliSense / lint / error checking | 每类 repository 包含 IntelliSense、code linting、error checking、help dialogs。 | 【事实】 | Code Repositories Overview |
| Preview | Transform preview 在输入样本上运行，输出样例，不提交、不跑 checks、不物化 dataset。 | 【事实】 | Preview transforms |
| Debug | Debugger 支持断点、变量、dataframe、函数和库检查；仅 Python。 | 【事实】 | Debug transforms |
| Repository types | 常见类型包含 Transforms、Functions、model development；Transforms 支持 Python/Java/SQL。 | 【事实】 | Code Repositories Overview |
| Transform 创建 | File template wizard 可选择 transform type，生成最小示例；Python transforms repository 会自动打开 wizard。 | 【事实】 | Create transforms |
| Template / dependency bootstrap | 生成文件时，如模板需要 backing dependencies/libraries，会自动配置以保证 transform 正常运行。 | 【事实】 | Create transforms |
| Repository upgrades | Foundry 会给活跃仓库生成 upgrade PR；可自动合并或由有权限用户处理。 | 【事实】 | Repository upgrades |
| Upgrade impact analysis | Upgrade PR 有 impact analysis tab，用于审查受影响 dataset 和 runtime Spark module 变化。 | 【事实】 | Repository upgrades |
| PR impact analysis | PR 页面展示受影响 dataset、stale dataset 提示、head/base branch 构建要求、数据访问限制。 | 【事实】 | Analyze the impact of changes |
| Unit tests | Code Repositories 支持通过 integrated helper 发现和运行多数语言、仓库类型的 unit tests。 | 【事实】 | Unit tests |
| Linter 治理 | Linter 定期 sweep 资源，生成 recommendations 和 fix proposal，并有 impact tracking。 | 【事实】 | Linter Overview / Impact tracking |

## 工程入口机制

### 1. Authoring：从资源上下文生成代码

Code Repositories 的 transform 创建不是空白仓库起步。官方的 file template configuration wizard 会让作者选择 transform type，并填写输入/输出 dataset 等变量，然后生成最小可运行示例。【事实】

该 wizard 会校验配置，例如输入输出资源必须与 repository 位于同一 project、参数名不能重复、必填参数必须存在；配置页面还会实时预览 transform 代码。【事实】

如果模板需要依赖或库，生成文件时会自动配置 backing dependencies/libraries；这意味着工程入口承担了一部分脚手架、资源绑定和依赖初始化职责。【事实】

### 2. Edit feedback：编辑期内建反馈

官方总览明确每类 repository 都包含 IntelliSense、code linting、error checking 和 rich help dialogs。【事实】

这类能力让高码入口更像“理解 Foundry 资源和语言模板的 IDE”，而不是一个仅包装 Git 的网页编辑器。【推断】

### 3. Branch/PR：生产分支通过策略进入

Code Repositories 的 sandbox branch 用于编辑代码，protected branches 不能直接编辑；生产或关键分支可配置为只能通过 PR 修改。【事实】

Protected branch 可配置 merge modes、要求 `ci/foundry-publish` 成功、要求代码评审、要求特定用户或组审批、根据文件路径配置 advanced approval policy，并在安全 marking 变更场景下要求 security checks/approval。【事实】

这表明 Palantir 的 PR 不只是源码合并动作，而是数据发布、权限、安全和仓库策略共同作用的控制点。【推断】

### 4. Preview/Debug：在构建前缩短反馈环

Preview 在有限样本上运行 transform，输出样例结果，不提交、不运行 checks、不物化 Foundry dataset；这直接面向 transform 开发的快速验证。【事实】

Debugger 可在 Code Repositories 中检查 transform 执行过程，包括断点、变量、dataframes、函数和库；但当前官方文档限定为 Python。【事实】

因此，对 Java/SQL transform，官方资料只能确认 preview 和 PR/build 相关路径，不能确认同等交互式 debugger 能力。【事实】

### 5. Impact analysis：PR 影响数据资产

Code edits 可能影响 dataset 内容、权限和结构；官方建议保护生产分支并在合并前 review proposed changes。【事实】

PR 页面会提示 affected datasets stale；影响评估要求 head branch 和 base branch 都用最新代码构建，以分别验证开发分支输出、Data Expectations，以及与目标分支最新输出对比。【事实】

Impact analysis 默认只显示直接受影响 dataset，不包括可能被连带影响的 derived datasets；用户可以添加更多 dataset 到分析中。查看受影响 dataset 需要数据访问权限，不可访问 dataset 会在 UI 标注为 inaccessible。【事实】

这说明 Palantir 把“代码 diff”扩展成“代码 diff 对数据资产的影响 diff”，但默认范围仍有边界，尤其 derived datasets 和 repo 外 parent datasets 需要额外注意。【推断】

### 6. Repository upgrades：平台运行时与模板生命周期

Foundry 会给 active repositories 生成 upgrade PR，包含 Transforms template 重要更新与 runtime improvements；upgrade PR 在专用分支打开，目标是 default branch。【事实】

启用 automatic upgrades 后，Foundry 会在 required checks 成功后自动合并 upgrade PR，并在 default branch commit history 中产生 merge commit。【事实】

自动升级仍会在多种场景要求人工处理，例如模板类型不支持 merge、用户修改了 upgrade PR 分支、upgrade 覆盖用户改动、受影响 dataset 未用最新代码构建、Spark module runtime 变化尚未构建、模板版本过旧等。【事实】

这让 Code Repositories 具备“平台模板和运行时演进入口”的角色；普通 Git 仓库通常不会自动把平台 runtime/template 升级以 PR 形式推给应用代码。【推断】

## 与普通 Git+CI 的差异

1. 普通 Git+CI 的基础语义是源码版本控制和任务执行；Code Repositories 的基础语义是 Foundry 资源上下文中的源码、数据资产、权限和运行时共同演进。【推断】
2. 普通 CI 可以跑测试、lint 和发布任务，但默认不知道 dataset 是否 stale、PR 会影响哪些 dataset、用户是否有权查看 affected dataset、Spark runtime module 升级会影响哪些输出。【推断】
3. Code Repositories 将 preview/debug 前移到 authoring 阶段，减少每次都触发完整 build 的需要；普通 Git+CI 通常需要本地环境、临时环境或 CI job 才能看到数据样本输出。【推断】
4. Protected branch 在 Palantir 中可与 `ci/foundry-publish`、review policy、安全 marking approval 等治理条件绑定；普通 Git 平台需要额外策略和外部系统集成才能达到同类语义。【推断】
5. Repository upgrades 把平台模板和 runtime 演进包装成 PR 和 impact analysis；普通 Git+CI 更常见的是依赖升级机器人或平台团队手工迁移，通常缺少 dataset impact 上下文。【推断】
6. Linter 的 recommendations/fix proposals/impact tracking 说明 Palantir 还有 enrollment 级别持续治理；普通 Git+CI 多以仓库为单位，跨资源优化通常依赖独立观测和治理平台。【推断】

## 对我们借鉴建议

1. 高码入口不应只做“在线编辑器 + Git”。应把代码、数据输入输出、运行时、权限、质量规则和发布策略绑定到同一个工程入口。【推断】
2. 创建 transform 时应提供模板 wizard，要求用户显式选择 transform 类型、输入输出资源、运行模式，并在生成前做资源/参数/依赖校验。【推断】
3. PR 页面应展示数据影响面：直接受影响 dataset、是否 stale、head/base 对比、质量规则结果、权限/marking 影响，以及不可访问资源提示。【推断】
4. 对生产分支应内建保护策略：必须 PR、必须发布检查通过、必须 review、可按路径/资源类型要求特定团队审批、安全策略变化必须额外审批。【推断】
5. Preview 应作为高码入口的一等能力：对样本数据执行 transform，不物化正式产物，用于缩短开发反馈环。【推断】
6. Debug 能力可先聚焦主语言，例如 Python，再逐步扩展；需要在产品文档中明确语言边界，避免用户误判。【推断】
7. 平台模板、SDK、运行时升级应以自动 PR 或升级任务进入仓库，并提供升级影响分析，不应只靠公告或手工迁移。【推断】
8. 建议补建类似 Linter 的平台治理通道：定期扫描资源与代码配置，提出成本、稳定性、维护性建议，并记录建议执行后的影响。【推断】

## 证据缺口

1. 官方公开文档没有展开 Code Repositories 权限模型的完整角色矩阵，例如 Owner、Editor、Viewer 在所有操作上的精确权限边界；当前只能从总览和 branch settings 中确认 PR/保护分支相关权限行为。【事实】
2. 官方文档确认每类 repository 有 lint/error checking，但没有在本次资料中展开具体 lint 规则、触发时机、语言覆盖和是否可配置；需要继续找 Code Repositories FAQ、language-specific docs 或产品截图。【事实】
3. Debugger 官方页面明确仅 Python；Java/SQL 是否有等价的运行期调试体验未确认，不能外推。【事实】
4. Impact analysis 默认仅显示 directly affected datasets；对跨 repository、repo 外 parent datasets、derived datasets 的完整影响闭环仍需要更多 Data Lineage / Branching / Data Health 资料补证。【事实】
5. Functions repository 和 model development 在总览中被确认，但本文件没有深挖其 repository 生命周期、PR checks 和 deployment path；后续应单独调研。【事实】
6. Repository upgrades 的实际 template 类型列表、版本兼容策略、失败恢复流程和与客户自定义文件的冲突处理细节仍未充分确认。【事实】
7. Palantir 是否支持外部 Git mirror、本地 clone、SSH/HTTPS Git remote、外部 CI 对接等能力，本次资料未验证。【猜测】

## 参考来源

- Palantir Docs - Code Repositories Overview: https://www.palantir.com/docs/foundry/code-repositories/overview/index.html
- Palantir Docs - Code Repositories / Create transforms: https://www.palantir.com/docs/foundry/code-repositories/create-transforms
- Palantir Docs - Code Repositories / Preview transforms: https://www.palantir.com/docs/foundry/code-repositories/preview-transforms
- Palantir Docs - Code Repositories / Debug transforms: https://www.palantir.com/docs/foundry/code-repositories/debug-transforms
- Palantir Docs - Code Repositories / Analyze the impact of changes: https://www.palantir.com/docs/foundry/code-repositories/analyze-impact
- Palantir Docs - Code Repositories / Branch settings: https://www.palantir.com/docs/foundry/code-repositories/branch-settings
- Palantir Docs - Code Repositories / Repository settings: https://www.palantir.com/docs/foundry/code-repositories/repository-settings
- Palantir Docs - Code Repositories / Repository upgrades: https://www.palantir.com/docs/foundry/code-repositories/repository-upgrades
- Palantir Docs - Code Repositories / Unit tests: https://www.palantir.com/docs/foundry/code-repositories/unit-tests
- Palantir Docs - Linter Overview: https://www.palantir.com/docs/foundry/linter/overview
- Palantir Docs - Linter Impact tracking: https://www.palantir.com/docs/foundry/linter/impact-tracking
