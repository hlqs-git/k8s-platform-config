# Repository Structure Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有空目录和 README 迁移为 Kustomize/Helm 友好、可逐步接入 Argo CD 的仓库结构。

**Architecture:** 公共平台组件保留在 `components/` 并新增 `base/` 入口；各实际集群在 `infrastructure/` 中表达平台能力，在 `policies/` 中表达治理策略，在 `apps/` 中表达业务选择。当前仅迁移目录和文档，不创建引用不存在资源的 `kustomization.yaml`。

**Tech Stack:** PowerShell、Markdown、Kustomize/Helm 目录约定

**Spec:** `docs/superpowers/specs/2026-09-15-repository-structure-design.md`

## Global Constraints

- 本次不安装 Argo CD 或 Flux。
- 本次不创建未经验证的 Kubernetes、Helm 或 Kustomize 业务清单。
- 不提交 kubeconfig、私钥或明文 Secret。
- 所有目录名使用小写 `kebab-case`。
- 只有实际需要的能力目录才存在；`registry/` 仅保留在 `k3s-office`。
- 当前工作区不是 Git 仓库，因此实施中不执行提交步骤。

---

### Task 1: 迁移三个集群目录

**Files:**
- Move: `clusters/k3s-office/cluster/` → `clusters/k3s-office/policies/`
- Move: `clusters/k3s-office/ingress/` → `clusters/k3s-office/infrastructure/ingress/`
- Move: `clusters/k3s-office/monitoring/` → `clusters/k3s-office/infrastructure/observability/`
- Move: `clusters/k3s-office/storage/` → `clusters/k3s-office/infrastructure/storage/`
- Move: `clusters/k3s-office/registry/` → `clusters/k3s-office/infrastructure/registry/`
- Move: `clusters/k8s-lab/cluster/` → `clusters/k8s-lab/policies/`
- Move: `clusters/k8s-lab/network/` → `clusters/k8s-lab/infrastructure/networking/`
- Move: `clusters/k8s-lab/ingress/` → `clusters/k8s-lab/infrastructure/ingress/`
- Move: `clusters/k8s-lab/monitoring/` → `clusters/k8s-lab/infrastructure/observability/`
- Move: `clusters/k8s-lab/storage/` → `clusters/k8s-lab/infrastructure/storage/`
- Move: `clusters/k8s-production/cluster/` → `clusters/k8s-production/policies/`
- Move: `clusters/k8s-production/network/` → `clusters/k8s-production/infrastructure/networking/`
- Move: `clusters/k8s-production/ingress/` → `clusters/k8s-production/infrastructure/ingress/`
- Move: `clusters/k8s-production/monitoring/` → `clusters/k8s-production/infrastructure/observability/`
- Move: `clusters/k8s-production/storage/` → `clusters/k8s-production/infrastructure/storage/`
- Preserve: `clusters/*/apps/`

**Interfaces:**
- Consumes: 当前集群分类目录中的 `.gitkeep` 与未来可能存在的配置文件。
- Produces: 每个集群稳定的 `infrastructure/`、`policies/`、`apps/` 边界。

- [x] **Step 1: 运行迁移前断言**

检查全部源目录存在、目标目录不存在，并将任何冲突作为硬错误停止迁移。

- [x] **Step 2: 创建三个 `infrastructure/` 父目录**

父目录必须位于当前工作区的 `clusters/<cluster>/` 内。

- [x] **Step 3: 使用同一 PowerShell 会话执行显式移动**

逐个使用 `Move-Item -LiteralPath <source> -Destination <target>`，不使用通配符或跨 Shell 拼接。

- [x] **Step 4: 验证集群目录**

断言 15 个目标目录存在、15 个旧目录不存在，三个 `apps/` 和集群 README 保持存在。

### Task 2: 建立公共组件入口

**Files:**
- Create: `components/{cert-manager,metallb,traefik,ingress-nginx,calico,cilium,prometheus,grafana,alertmanager,harbor,juicefs,weka}/base/.gitkeep`
- Create: `components/{cert-manager,metallb,traefik,ingress-nginx,calico,cilium,prometheus,grafana,alertmanager,harbor,juicefs,weka}/README.md`
- Remove after migration: each component root `.gitkeep`

**Interfaces:**
- Consumes: 12 个现有公共组件目录。
- Produces: 每个组件的公共 `base/` 入口和职责文档。

- [x] **Step 1: 验证 12 个组件目录存在**

若组件目录缺失或已经包含非占位内容，停止对应组件的机械迁移并报告冲突。

- [x] **Step 2: 创建 `base/` 目录并迁移占位文件**

每个 `base/` 中保留 `.gitkeep`，组件根目录不再保留 `.gitkeep`。

- [x] **Step 3: 创建组件 README**

每份 README 明确组件用途、配置入口、集群差异归属、版本/来源/依赖/升级/回滚记录字段，并声明未加入实际资源前不创建空 `kustomization.yaml`。

- [x] **Step 4: 验证组件入口**

断言 12 个 `base/.gitkeep` 和 12 个 README 存在，组件根目录 `.gitkeep` 不存在。

### Task 3: 调整脚本职责

**Files:**
- Move: `scripts/install/` → `scripts/deploy/`
- Create: `scripts/validate/.gitkeep`

**Interfaces:**
- Consumes: 当前 `scripts/install/` 占位目录。
- Produces: 手工部署入口 `deploy/` 和验证入口 `validate/`。

- [x] **Step 1: 验证源路径和目标冲突**

断言 `scripts/install/` 存在，`scripts/deploy/` 与 `scripts/validate/` 不存在。

- [x] **Step 2: 移动部署目录并创建验证目录**

将整个 `install/` 移到 `deploy/`，创建 `validate/` 并添加 `.gitkeep`。

- [x] **Step 3: 验证脚本目录**

断言 `deploy/`、`validate/`、`backup/`、`restore/`、`troubleshooting/` 存在，`install/` 不存在。

### Task 4: 更新仓库文档

**Files:**
- Modify: `README.md`
- Modify: `clusters/k3s-office/README.md`
- Modify: `clusters/k8s-lab/README.md`
- Modify: `clusters/k8s-production/README.md`
- Modify: `secrets/README.md`

**Interfaces:**
- Consumes: Tasks 1–3 产生的真实目录结构。
- Produces: 与真实路径一致的仓库使用说明。

- [x] **Step 1: 更新根目录树与职责说明**

将旧的 `cluster/network/ingress/monitoring/storage/registry` 描述替换为 `infrastructure/policies/apps`，补充 `scripts/deploy` 与 `scripts/validate`。

- [x] **Step 2: 更新三个集群 README**

按各集群实际能力列出 `infrastructure/` 子目录，将治理资源说明改为 `policies/`，保持环境信息和部署检查清单不变。

- [x] **Step 3: 更新 Secret 归属说明**

明确顶层 `secrets/` 只保存规范与全局加密策略，加密声明或 Secret 引用靠近所属组件、应用或集群覆盖目录。

- [x] **Step 4: 扫描旧路径引用**

运行 Markdown 全库搜索；不允许普通文档继续将旧路径描述为当前结构。设计与实施计划中的迁移映射可以保留旧路径。

### Task 5: 完整验收

**Files:**
- Verify: entire repository tree

**Interfaces:**
- Consumes: Tasks 1–4 的全部结果。
- Produces: 满足设计文档验证标准的最终目录与文档。

- [x] **Step 1: 校验目标目录与文件清单**

PowerShell 逐项检查集群目标目录、组件 base/README、脚本目录和全部顶层 README。

- [x] **Step 2: 校验旧目录已清理**

逐项断言迁移映射中的旧目录不存在；不使用模糊的名称搜索替代路径断言。

- [x] **Step 3: 校验没有空 `kustomization.yaml`**

在首批真实 Kubernetes 资源加入前，仓库中不应存在仅为占位而创建的 `kustomization.yaml`。

- [x] **Step 4: 校验敏感文件模式**

列出仓库文件并检查私钥、kubeconfig、`.env`、临时解密文件等禁止模式；检查只验证文件名和受控文档，不输出任何潜在敏感文件内容。

- [x] **Step 5: 输出最终目录树**

确认命令退出码为 0，并报告迁移数量、文档数量及当前不是 Git 仓库这一限制。
