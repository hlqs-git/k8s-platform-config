# k8s-production

生产 Kubernetes 集群的最终期望状态。此目录中的变更应经过评审、预生产验证，并具备明确的部署与回滚步骤。

## 集群信息

| 项目 | 内容 |
| --- | --- |
| 环境 | Production |
| Kubernetes 安装方式 | kubeadm / Kubespray，待确认 |
| Kubernetes 版本 | 待填写 |
| 节点与角色 | 待填写 |
| API Server 地址 | 待填写；不要提交带凭据的 kubeconfig |
| CNI | 待填写 |
| 默认 StorageClass | 待填写 |
| Ingress Controller | 待填写 |
| 集群域名/入口域名 | 待填写 |
| 监控与告警入口 | 待填写 |
| 维护负责人 | 待填写 |

## 目录职责

- `infrastructure/networking/`：CNI、地址池、DNS 和生产网络配置。
- `infrastructure/ingress/`：Ingress Controller、生产入口规则和证书引用。
- `infrastructure/observability/`：生产指标、日志、链路追踪、告警规则及通知配置。
- `infrastructure/storage/`：StorageClass、CSI、快照与持久化存储配置。
- `policies/`：Namespace、RBAC、资源配额、NetworkPolicy 和准入策略。
- `apps/`：生产业务应用及其集群专属参数。

## 推荐部署顺序

1. 网络与集群基础资源。
2. 存储和数据保护能力。
3. Ingress 与证书能力。
4. 监控、日志和告警。
5. 业务应用。

组件之间存在依赖时，应拆分部署单元并明确先后关系。不要依赖文件名排序隐式控制生产部署顺序。

## 生产变更要求

- 所有镜像和 Chart 使用明确、可追溯的版本或 digest。
- 重要变更先在 `k8s-lab` 验证，并记录验证结果。
- 修改 CRD、CNI、CSI、Ingress Controller 或存储配置前，必须准备回滚方案。
- 工作负载应设置合理的 requests、limits、健康检查、PodDisruptionBudget 和副本策略。
- 高可用服务应检查反亲和、拓扑分布和节点维护影响。
- 数据服务变更前确认备份可用，并完成恢复演练或恢复路径核验。
- 部署完成后观察关键指标、事件、错误率和告警，再结束变更窗口。

## 回滚记录模板

```text
触发条件：
回滚负责人：
上一稳定版本：
回滚命令/步骤：
数据兼容性说明：
回滚后验证项：
```

## 部署前检查

- [ ] 已确认目标 kube-context 为生产集群。
- [ ] 变更已评审，并在实验环境验证。
- [ ] 最终清单可以成功渲染和检查差异。
- [ ] 镜像与依赖版本固定，来源可信。
- [ ] Secret 仅通过受控方案引用或生成。
- [ ] 备份、回滚步骤和变更窗口已确认。
- [ ] 部署后验证指标和负责人已明确。
