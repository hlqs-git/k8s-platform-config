# Kubernetes 配置仓库目录优化设计

日期：2026-09-15

## 背景

仓库当前按集群、公共组件、集群初始化、运维脚本、文档和 Secret 规范分层，整体方向合理。但 `components/` 中的公共组件与 `clusters/<cluster>/{network,ingress,monitoring,storage,...}` 中的最终配置之间缺少统一的组合入口，后续容易出现 YAML 复制、部署顺序依赖人工记忆、集群实际状态难以对应 Git 目录等问题。

当前由个人维护，近期采用 Kustomize 与 Helm 手工触发部署；目录同时为未来接入 Argo CD 或 Flux 保留稳定入口。

## 目标

- 每个集群目录具备唯一、明确的期望状态入口。
- 公共组件与集群差异分离，避免复制整套组件清单。
- 明确基础设施、策略、业务应用和集群创建配置的职责边界。
- 同时支持 Kustomize、Helm 手工部署及后续 GitOps 自动同步。
- 允许按组件逐步迁移，不要求一次性引入所有实际资源。

## 非目标

- 本次不安装 Argo CD 或 Flux。
- 本次不创建未经验证的 Kubernetes、Helm 或 Kustomize 业务清单。
- 本次不确定具体集群版本、节点地址、域名或 Secret 后端。
- 本次不为只有单一实例的配置强行建立多层抽象。

## 方案选择

采用“Kustomize 优先、Helm 兼容、GitOps-ready”的单仓库结构。

Kustomize 负责组合公共资源与集群差异；第三方组件继续使用上游 Helm Chart 时，在组件目录保存版本与默认 values，在集群目录保存该集群的 values 或声明式 release 配置。集群目录作为最终入口，未来 Argo CD 或 Flux 只需指向该入口，无须再次调整业务目录。

## 目标结构

```text
k8s-platform-config/
├── clusters/
│   ├── k3s-office/
│   │   ├── infrastructure/
│   │   │   ├── ingress/
│   │   │   ├── observability/
│   │   │   ├── registry/
│   │   │   └── storage/
│   │   ├── policies/
│   │   ├── apps/
│   │   ├── kustomization.yaml
│   │   └── README.md
│   ├── k8s-lab/
│   │   ├── infrastructure/
│   │   │   ├── networking/
│   │   │   ├── ingress/
│   │   │   ├── observability/
│   │   │   └── storage/
│   │   ├── policies/
│   │   ├── apps/
│   │   ├── kustomization.yaml
│   │   └── README.md
│   └── k8s-production/
│       ├── infrastructure/
│       │   ├── networking/
│       │   ├── ingress/
│       │   ├── observability/
│       │   └── storage/
│       ├── policies/
│       ├── apps/
│       ├── kustomization.yaml
│       └── README.md
├── components/
│   └── <component>/
│       ├── base/
│       └── README.md
├── bootstrap/
│   ├── k3s/
│   └── kubernetes/
├── scripts/
│   ├── deploy/
│   ├── validate/
│   ├── backup/
│   ├── restore/
│   └── troubleshooting/
├── docs/
└── secrets/
```

只有实际需要的子目录才创建。例如办公室集群保留 `registry/`，其他集群在需要前不创建空的 Registry 目录。

## 职责边界

### `clusters/`

每个目录对应一个实际集群，包含该集群最终启用的基础设施、策略和应用。根 `kustomization.yaml` 是集群级渲染入口，按依赖组合资源；未来 GitOps 控制器也以该目录为同步入口。

### `clusters/<cluster>/infrastructure/`

放置集群运行所需的平台能力及集群专属覆盖：

- `networking/`：CNI、地址池、DNS 与网络平台配置。
- `ingress/`：Ingress Controller、入口平台与证书引用。
- `observability/`：指标、日志、链路追踪及告警。
- `storage/`：CSI、StorageClass、VolumeSnapshot 与存储平台配置。
- `registry/`：集群专属镜像仓库能力，仅在实际使用的集群创建。

目录名使用能力名称，不使用具体产品名称；具体产品由该目录中的引用决定，从 Calico 切换到 Cilium 时无需改变上层入口。

### `clusters/<cluster>/policies/`

保存 Namespace、RBAC、ResourceQuota、LimitRange、NetworkPolicy、Pod 安全与准入策略。原 `cluster/` 中属于集群创建后的治理资源迁入此处。集群安装参数仍留在 `bootstrap/`。

### `clusters/<cluster>/apps/`

保存部署到该集群的业务应用选择及集群差异。应用自身的公共部署定义可来自应用代码仓库或本仓库中后续建立的公共应用目录，不复制平台组件清单。

### `components/`

一个目录对应一个可复用平台组件，例如 cert-manager 或 ingress-nginx。每个组件至少包含 `README.md` 和 `base/`：

- `README.md`：用途、来源、固定版本、依赖、升级和回滚说明。
- `base/`：Kustomize 公共资源，或 Helm Chart 的版本声明与公共 values。

集群差异不放入组件 `base/`。仅当多个集群确实共享同一种变体时才新增组件级 `overlays/`，避免提前抽象。

### `bootstrap/`

只负责把机器创建成可用 Kubernetes/K3s 集群，包括 K3s 安装参数、kubeadm 配置和 Kubespray inventory。集群创建后的 CNI、CSI、Ingress、监控和业务工作负载由 `clusters/` 管理。

### `scripts/`

- `deploy/`：统一封装手工渲染、diff、应用和部署后检查。
- `validate/`：YAML、Kustomize、Helm、策略和 Secret 扫描。
- `backup/`、`restore/`、`troubleshooting/`：保留原有职责。

原 `scripts/install/` 删除；集群安装属于 `bootstrap/`，集群创建后的部署属于 `scripts/deploy/`。

### `secrets/`

顶层目录只保留安全规范与全局加密策略。加密后的 Secret 或 ExternalSecret 应靠近其所属组件、应用或集群覆盖目录，以便所有权和生命周期一致。

## 配置组合规则

1. `components/<component>/base/` 不引用任何集群目录。
2. `clusters/<cluster>/infrastructure/<capability>/` 可以引用一个或多个公共组件并应用最小差异。
3. `clusters/<cluster>/kustomization.yaml` 只组合该集群需要的资源，不包含真实 Secret。
4. 小补丁只解决一个差异，并使用能表达意图的文件名。
5. Helm 组件固定 Chart 版本；集群 values 只覆盖与公共默认值不同的部分。
6. 应用部署顺序通过显式依赖或拆分同步单元表达，不依赖文件名字典序。

## 迁移映射

| 当前路径 | 目标路径 |
| --- | --- |
| `clusters/*/cluster/` | `clusters/*/policies/` |
| `clusters/*/network/` | `clusters/*/infrastructure/networking/` |
| `clusters/*/ingress/` | `clusters/*/infrastructure/ingress/` |
| `clusters/*/monitoring/` | `clusters/*/infrastructure/observability/` |
| `clusters/*/storage/` | `clusters/*/infrastructure/storage/` |
| `clusters/k3s-office/registry/` | `clusters/k3s-office/infrastructure/registry/` |
| `clusters/*/apps/` | `clusters/*/apps/`，路径保持不变 |
| `scripts/install/` | 删除；安装资料归入 `bootstrap/`，部署脚本归入 `scripts/deploy/` |

## 分阶段采用 GitOps

### 当前阶段

- Kustomize 渲染自建资源。
- Helm 管理第三方 Chart。
- 手工执行 validate、diff、deploy 和 verify。
- Git 保存全部非敏感期望状态与版本信息。

### GitOps 试运行阶段

先在 `k8s-lab` 安装 Argo CD，将 `clusters/k8s-lab/` 设置为入口。初期启用状态检测但保留手工同步，不全局开启自动 prune 或 self-heal。

### 自动同步阶段

实验集群稳定后再为低风险资源开启自动同步，并逐类推广到生产。Namespace、PVC、CRD 等高风险资源保留删除确认或独立同步边界。

## 安全与故障边界

- 仓库中不提交 kubeconfig、私钥或明文 Secret。
- 每次手工部署前校验 kube-context，并对生产环境要求显式确认。
- 渲染与 diff 成功后才能应用；生产变更必须记录回滚方法。
- GitOps 自动同步错误时，应能暂停对应 Application/Kustomization，而不影响其他部署单元。
- GitOps 控制器自身的安装与恢复说明属于 `bootstrap/` 或灾难恢复文档，不与其管理的业务状态形成不可恢复的循环依赖。

## 验证标准

目录迁移完成后应满足：

1. 旧分类目录不存在，所有占位文件已迁入对应新目录。
2. 每个集群都有 `infrastructure/`、`policies/`、`apps/` 和 README。
3. README 中的目录树、路径与实际目录一致。
4. 公共组件均具备 `base/` 与 README 占位入口。
5. `scripts/deploy/` 和 `scripts/validate/` 存在，`scripts/install/` 不再存在。
6. 不创建引用不存在资源的 `kustomization.yaml`；在加入首批实际资源时再创建可渲染入口。
7. Secret 扫描不发现明文凭据或私钥材料。

## 实施顺序

1. 迁移集群分类目录并保留现有 README。
2. 为公共组件增加 `base/` 和 README 占位入口。
3. 调整脚本目录。
4. 更新根 README、集群 README 和 Secret 文档中的路径与职责。
5. 验证实际目录树、旧路径清理和文档引用。

本次仅迁移空目录和文档，不创建虚假的部署清单；实际组件进入仓库时，再按上述边界逐一补充可渲染配置。
