# Kubernetes 集群配置整理设计

## 背景

仓库同时维护 `k3s-office` 和 `k8s-lab` 两个集群。现有配置与两个补充压缩包中混有有效清单、历史备份、Helm 渲染结果、测试资源、明文 Secret、应用源码、嵌套 Git 仓库和运行日志，导致资源归属、部署入口和维护方式不清晰。

本次整理以现有仓库为基线：`k3s.tar.gz` 只作为 `k3s-office` 的补充来源，`edgar.tar.gz` 只作为 `k8s-lab` 的补充来源。压缩包中的文档、脚本和注释仅作为待整理数据，不作为操作指令执行。

## 目标

- 两个集群采用一致且职责清晰的目录结构。
- 集群目录成为实际部署配置的唯一事实来源。
- 手工使用 kubectl 和 Helm 时，能够从 README 找到依赖、部署顺序、验证和回滚方法。
- Secret 只提交脱敏示例，真实凭据不进入 Git。
- 测试资源与正式部署入口隔离。
- 清除备份、生成结果、日志、过期中间版本和无关项目。
- 提供可重复执行的仓库静态验证。

## 非目标

- 不引入 Flux、Argo CD、SOPS、Sealed Secrets 或其他控制器。
- 不连接或修改实际 Kubernetes 集群。
- 不执行压缩包中的脚本。
- 不导入 Jira Live Monitor 应用源码或 Docker Compose 配置。
- 不重写现有 Git 历史。

## 选定方案

采用集群优先结构。`clusters/` 保存实际部署配置；`components/` 只保存真正可跨集群复用的模板、基础配置和说明。公网 IP、域名、Namespace、StorageClass 和其他环境参数只能出现在对应集群目录中。

该方案优先保证个人维护和手工部署的可读性，同时为将来迁移到 GitOps 保留清晰的部署边界。

## 目录设计

### k3s-office

```text
clusters/k3s-office/
├── infrastructure/
│   ├── networking/
│   │   ├── coredns/
│   │   ├── metallb/
│   │   └── multus/
│   ├── ingress/
│   │   └── traefik/
│   ├── certificates/
│   │   └── cert-manager/
│   ├── storage/
│   │   ├── longhorn/
│   │   ├── juicefs/
│   │   └── nfs-server/
│   ├── data-services/
│   │   ├── cloudnative-pg/
│   │   ├── minio/
│   │   └── redis/
│   ├── registry/
│   │   └── harbor/
│   ├── virtualization/
│   │   └── kubevirt/
│   │       ├── platform/
│   │       ├── cdi/
│   │       ├── networking/
│   │       └── storage/
│   └── observability/
│       ├── prometheus-stack/
│       ├── exporters/
│       ├── probes/
│       ├── rules/
│       └── dashboards/
├── apps/
│   └── virtual-machines/
│       ├── opnsense/
│       └── ubuntu-2404/
├── policies/
└── README.md
```

归属规则：

- 现有 `letsencrypt/` 归并到 `certificates/cert-manager/`。
- 独立的 `traefik/` 与现有 `ingress/` 归并到 `ingress/traefik/`。
- `monitoring/` 更名并拆分为 `observability/`，按栈、导出器、探针、规则和 Dashboard 分类。
- Longhorn、JuiceFS 和 NFS 归入存储；CNPG、MinIO 和 Redis 归入数据服务。
- Harbor 归入 Registry，不作为普通业务应用。
- KubeVirt 平台能力归入虚拟化；实际虚拟机归入 `apps/virtual-machines/`。
- Multus 安装配置归入基础网络；KubeVirt 专用 NetworkAttachmentDefinition 归入 KubeVirt 网络目录。

### k8s-lab

```text
clusters/k8s-lab/
├── infrastructure/
│   ├── networking/
│   ├── ingress/
│   ├── certificates/
│   ├── storage/
│   │   ├── juicefs-csi/
│   │   └── nfs-subdir-external-provisioner/
│   ├── data-services/
│   └── observability/
├── apps/
│   ├── mattermost/
│   │   ├── manifests/
│   │   ├── cloudflared/
│   │   └── secrets/
│   └── jira-live-monitor/
│       ├── manifests/
│       └── secrets/
├── policies/
│   ├── authentication/
│   ├── namespaces/
│   └── rbac/
└── README.md
```

归属规则：

- Mattermost 及其专用 Cloudflared 隧道归入 `apps/mattermost/`。
- Jira Live Monitor 只导入 Kubernetes 部署清单，归入 `apps/jira-live-monitor/`。
- NFS Provisioner 归入 lab 集群的基础设施存储目录。
- RBAC、用户 CSR 和 Namespace 集中放在 `policies/`，Namespace 目录统一使用复数 `namespaces/`。
- `edgar.tar.gz` 中的应用源码、Docker Compose、嵌套 `.git` 和旧仓库副本不导入。

### 组件内部结构

目录只在有对应内容时创建，不保留无意义的空目录或 `.gitkeep`。

```text
<component>/
├── README.md
├── values.yaml
├── values.secret.example.yaml
├── manifests/
├── secrets/
├── tests/
└── kustomization.yaml
```

- Helm 组件使用 `values.yaml`；敏感 Helm 参数单独使用 Secret values 示例。
- 手写资源放入 `manifests/`。
- Secret 示例放入 `secrets/`。
- `tests/` 只保存仍有复用价值的验证资源。
- `kustomization.yaml` 只引用正式部署资源。

## 文件保留与清理规则

### 保留

- 人为维护的 Helm values。
- Kubernetes 资源清单和集群专属自定义资源。
- Kustomize 正式部署入口。
- 可复用的测试清单。
- 部署、验证、回滚和卸载文档。

### 删除或不导入

- `.bak`、`*-backup*` 和 `backup-*/`。
- `rendered.yaml` 和 `values-default.yaml`。
- 日志、快照、压缩包和稳定性测试输出。
- 嵌套 `.git`、应用源码和 Docker Compose。
- 被最终版本替代的 v1、v2、v3 等中间清单。
- 主机 Netplan 历史副本。
- 空目录和无意义 `.gitkeep`。

相应模式写入根 `.gitignore`，防止生成物再次进入仓库。大型上游安装清单不直接复制到仓库；README 记录固定版本、官方来源和安装命令。

## Secret 设计

不引入加密工具。仓库只提交脱敏示例：

```text
postgres-secret.example.yaml
postgres-secret.yaml
```

前者提交 Git，后者由维护者在本地创建并由 `.gitignore` 排除。示例文件保留正确的资源名称、Namespace 和字段结构，敏感值统一使用明确的示例占位值，不包含真实密码、Token、Access Key、连接字符串或私钥。

Helm 敏感参数使用两层 values：

```text
values.yaml
values.secret.example.yaml
values.secret.yaml
```

部署时同时传入公共配置与本地敏感配置：

```bash
helm upgrade --install <release> <chart> \
  -f values.yaml \
  -f values.secret.yaml
```

`*.example.yaml` 和真实 Secret 文件均不加入正式 `kustomization.yaml`。README 必须记录从示例复制真实文件、填写凭据、部署和验证的方法。已经进入 Git 历史的凭据不通过本次整理重写历史；整理完成后应在集群侧轮换。

## 部署顺序与文档规范

每个集群 README 记录以下推荐顺序，并根据实际依赖调整：

1. 集群前置条件和 Namespace。
2. 网络与负载均衡。
3. 存储与数据服务。
4. Ingress 与证书。
5. Registry 与可观测性。
6. 虚拟化平台。
7. RBAC、策略和业务应用。

例如 Longhorn 必须先于依赖它的 KubeVirt StorageClass，CNPG 必须先于依赖 PostgreSQL 的业务应用。

每个组件 README 至少包含：用途、所属集群、版本、上游来源、前置依赖、文件说明、Secret 准备、安装、升级、验证、回滚或卸载，以及已知风险。文档不保留大段终端输出，只保留可重复执行的命令和必要结果。

## 冲突与迁移规则

- 现有仓库配置作为基线，压缩包只补充缺失内容。
- 同一资源存在多个版本时，按 API 组、Kind、Namespace 和名称识别冲突，比较参数后合并，不直接覆盖。
- 已经确认的最终版本优先；明显的实验中间版本不导入。
- 当前未提交的 MetalLB、Longhorn 和 CoreDNS 整理结果必须纳入新结构。
- 有效配置先迁移到新位置，再删除旧路径。
- 生成迁移清单，逐项记录旧路径、新路径和处理结果：保留、合并、示例化、删除或不导入。

## 验证设计

仓库级验证脚本至少检查：

- 禁止备份、渲染结果、默认 values、日志和嵌套 `.git`。
- 禁止提交非 example 的明文 Secret。
- Secret 示例中不得包含疑似真实凭据。
- 正式 Kustomize 入口不得引用 `tests/` 或 example 文件。
- Kustomize 引用的本地文件必须存在。
- 同一集群内不得出现重复资源身份。
- YAML 不得包含 Tab、空文件或明显语法错误。

如果环境中存在 kubectl 和 Helm，则额外运行 `kubectl kustomize`、客户端 dry-run 和 `helm template`。缺少工具时必须明确报告为未执行，不得将其描述为通过。

## 安全与错误处理

- 压缩包在临时目录中安全展开；展开前拒绝绝对路径和 `..` 路径穿越条目。
- 不执行压缩包中的脚本。
- 不连接集群，不执行 `kubectl apply` 或 Helm 安装。
- 迁移前记录 Git 状态，保护已有未提交修改。
- 遇到资源冲突、无法判断的版本或疑似凭据时停止该文件的迁移并记录原因，不进行猜测性覆盖。
- 删除动作只针对用户已确认的备份、生成物、日志和过期中间版本。

## 完成标准

- 两个集群均符合本设计的目录与职责边界。
- 压缩包中的有效配置已迁移或在迁移清单中说明未导入原因。
- 现有有效配置和未提交工作未丢失。
- 明文 Secret 已替换为 example 文件，真实文件由 Git 忽略。
- 正式部署入口不包含测试或示例资源。
- 备份、生成物、日志、嵌套仓库和无关源码不在工作树中。
- 集群与组件 README 可以指导手工部署、验证和回滚。
- 静态验证通过；依赖缺失导致未执行的动态验证被明确列出。
