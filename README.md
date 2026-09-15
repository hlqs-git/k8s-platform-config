# Kubernetes Platform Config

集中管理多个 Kubernetes/K3s 集群的声明式配置、可复用平台组件、集群初始化资料、运维脚本和操作文档。

## 仓库目标

- 让每个集群的期望状态可以被审查、复现和追踪。
- 复用公共组件配置，同时将集群差异保留在对应集群目录中。
- 将集群初始化、日常部署、备份恢复和故障排查资料放在同一入口下。
- 避免在 Git 中保存明文凭据和集群访问配置。

## 集群一览

| 目录 | 类型 | 定位 | 说明 |
| --- | --- | --- | --- |
| `clusters/k3s-office/` | K3s | 办公环境 | 轻量级办公服务与内部应用 |
| `clusters/k8s-lab/` | Kubernetes | 实验环境 | 组件验证、升级演练与技术测试 |
| `clusters/k8s-production/` | Kubernetes | 生产环境 | 正式业务工作负载 |

集群版本、节点、入口域名、存储类型等环境信息记录在各集群的 `README.md` 中。

## 目录结构

```text
.
├── clusters/       # 各实际集群的最终配置和集群差异
├── components/     # 可复用的平台组件配置
├── bootstrap/      # K3s/Kubernetes 创建与初始化资料
├── scripts/        # 部署、验证、备份、恢复和故障排查脚本
├── docs/           # 架构、部署、网络、存储和排障文档
└── secrets/        # Secret 管理约定，不保存明文敏感数据
```

### `clusters/`

一个目录对应一个真实集群。集群目录描述该集群的最终期望状态，而不是公共组件的完整副本。

- `infrastructure/`：集群运行所需的平台能力及其集群专属覆盖。
  - `networking/`：CNI、地址池、DNS 与网络平台配置；K3s 使用内置网络且无需覆盖时可以省略。
  - `ingress/`：Ingress Controller、入口规则及证书引用。
  - `observability/`：指标、日志、链路追踪和告警配置。
  - `storage/`：StorageClass、CSI、快照和持久化存储配置。
  - `registry/`：镜像仓库配置；当前仅办公室集群维护。
- `policies/`：Namespace、RBAC、ResourceQuota、LimitRange、NetworkPolicy 和准入策略。
- `apps/`：部署到该集群的业务应用及集群专属参数。

### `components/`

保存 cert-manager、Ingress Controller、监控、镜像仓库和存储等可复用组件。公共资源应在这里维护；集群目录仅引用公共配置并覆盖必要差异，避免复制整套 YAML。

每个组件当前至少包含：

```text
components/<name>/
├── README.md             # 用途、依赖、版本和升级说明
├── base/                 # 通用资源或默认 Helm values
└── overlays/             # 确有共享环境变体时再创建
```

如果一个组件只用于单一集群，优先放在对应集群目录中，不必为了“复用”而过度抽象。

### `bootstrap/`

- `k3s/install/`、`k3s/config/`：K3s 安装与节点配置。
- `kubernetes/kubeadm/`：kubeadm 初始化配置。
- `kubernetes/kubespray/`：Kubespray inventory 与变量。

Bootstrap 只负责创建可用集群。集群创建后的长期期望状态应放在 `clusters/`，避免职责交叉。

### `scripts/` 与 `docs/`

脚本按操作目的分类：`deploy/` 负责手工渲染、diff、应用和部署后检查，`validate/` 负责配置与安全检查，其他目录负责备份、恢复和故障排查。脚本必须支持明确参数，并在执行危险操作前给出提示。较长流程写入 `docs/`，脚本 README 或注释链接到相应文档。

## 配置原则

1. **声明式优先**：可由 YAML、Helm values 或 Kustomize 表达的状态不要只保存在命令历史中。
2. **公共配置与集群差异分离**：公共默认值放 `components/`，集群选择和覆盖放 `clusters/`。
3. **一个入口描述一个部署单元**：每个可部署目录应有清晰入口，例如 `kustomization.yaml`、`Chart.yaml` 或说明部署命令的 README。
4. **固定版本**：镜像、Chart 和依赖使用明确版本；生产环境避免浮动标签。
5. **变更可验证**：合并前完成渲染、语法检查和服务端 dry-run（集群可用时）。
6. **生产变更可回滚**：升级前记录当前版本、变更内容和回滚方法。

## 推荐部署顺序

```text
集群初始化
  → 网络与 DNS
  → 存储
  → Ingress 与证书
  → 监控与告警
  → 镜像仓库等平台服务
  → 业务应用
```

实际顺序以目标集群 README 和组件依赖为准。

## 基本工作流

1. 在 `components/<component>/base/` 修改公共配置，或在 `clusters/<cluster>/infrastructure/`、`policies/`、`apps/` 修改集群专属配置。
2. 在本地渲染最终清单并检查差异；使用 Kustomize 时可执行 `kubectl kustomize <path>` 和 `kubectl diff -k <path>`。
3. 检查 Namespace、镜像版本、资源限制、存储类、入口域名和 Secret 引用。
4. 先在实验集群验证高风险组件升级，再推广到生产集群。
5. 部署后检查 Pod、事件、入口、告警和持久化数据状态。
6. 将验证结果和必要的回滚说明记录到变更单或提交说明中。

## 命名约定

- 目录和 Kubernetes 资源名使用小写 `kebab-case`。
- 集群目录采用 `<distribution>-<environment>`，例如 `k3s-office`。
- 文件名体现资源用途，例如 `namespace.yaml`、`network-policy.yaml`、`values.yaml`。
- 集群专属覆盖文件应明确指出目标集群或用途，避免 `new.yaml`、`final.yaml` 等模糊名称。

## Secret 安全

禁止提交明文密码、Token、私钥、证书私钥或 kubeconfig。Kubernetes Secret 中的 Base64 只是编码，不是加密。详细规则见 [`secrets/README.md`](secrets/README.md)。

## 变更检查清单

- [ ] 修改位于正确的公共组件或目标集群目录。
- [ ] 不包含明文凭据、私钥、kubeconfig 或临时解密文件。
- [ ] 镜像、Chart 和外部依赖版本明确。
- [ ] CPU/内存 requests 与 limits 合理。
- [ ] Namespace、RBAC、StorageClass、域名和 Secret 引用正确。
- [ ] 已渲染并检查最终清单。
- [ ] 高风险或生产变更包含验证与回滚步骤。

## 文档维护

新增集群、平台组件或运维流程时，应同步更新相关 README。尚未确定的真实环境信息使用 `待填写` 标记，不要填入猜测值。
