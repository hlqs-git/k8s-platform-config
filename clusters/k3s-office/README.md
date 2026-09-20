# k3s-office

办公室 K3s 集群的最终期望状态，用于承载内部平台服务和办公应用。

## 集群信息

| 项目 | 内容 |
| --- | --- |
| 环境 | Office |
| Kubernetes 发行版 | K3s |
| K3s/Kubernetes 版本 | 待填写 |
| 节点与角色 | 待填写 |
| API Server 地址 | 待填写；不要提交带凭据的 kubeconfig |
| 默认 StorageClass | Longhorn |
| Ingress Controller | K3s Traefik |
| 集群域名/入口域名 | 待填写 |
| 维护负责人 | 待填写 |

## 目录职责

- `infrastructure/networking/`：CoreDNS 高可用设置、MetalLB 地址池和 L2 网络配置。
- `infrastructure/ingress/`：Ingress Controller、入口规则和证书引用。
- `infrastructure/observability/`：指标、日志、链路追踪和告警规则。
- `infrastructure/storage/`：StorageClass、CSI 或本地存储配置。
- `infrastructure/registry/`：办公室环境使用的镜像仓库配置。
- `policies/`：Namespace、RBAC、资源配额、NetworkPolicy 和准入策略。
- `apps/`：内部应用及其集群专属配置。

K3s 自带组件的启用/禁用参数放在 `bootstrap/k3s/config/`，其安装后的声明式资源放在本目录，避免安装配置和运行状态混在一起。

## 推荐部署顺序

1. 使用 `bootstrap/k3s/` 完成集群安装和节点配置。
2. 配置 `infrastructure/networking/`，并确认 CoreDNS、MetalLB 和入口地址正常。
3. 应用 `policies/` 中的治理资源。
4. 配置 `infrastructure/storage/`。
5. 配置 `infrastructure/ingress/` 和证书能力。
6. 部署 `infrastructure/observability/`。
7. 部署 `infrastructure/registry/`。
8. 部署 `apps/`。

## 变更注意事项

- 确认 K3s 内置 Traefik、ServiceLB 等组件是否启用，避免与独立部署的 Ingress Controller 或 MetalLB 冲突。
- 单节点或资源受限场景下，升级前检查磁盘空间、内存和可用备份。
- 使用本地存储时记录数据所在节点，并验证节点故障后的恢复方式。
- 修改入口或证书配置后，验证内网 DNS、TLS 和后端服务健康状态。

## 部署前检查

- [ ] 已确认目标 kube-context，且不是其他集群。
- [ ] 最终清单可以成功渲染。
- [ ] Secret 仅通过受控方案引用或生成。
- [ ] 镜像仓库、存储和入口依赖已经就绪。
- [ ] 变更后已检查 Pod、事件、Ingress 和持久化卷状态。
