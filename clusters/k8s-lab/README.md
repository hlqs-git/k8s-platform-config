# k8s-lab

实验室 Kubernetes 集群的最终期望状态，用于平台组件验证、版本升级演练和非生产工作负载测试。

## 集群信息

| 项目 | 内容 |
| --- | --- |
| 环境 | Lab |
| Kubernetes 安装方式 | kubeadm / Kubespray，待确认 |
| Kubernetes 版本 | 待填写 |
| 节点与角色 | 待填写 |
| API Server 地址 | 待填写；不要提交带凭据的 kubeconfig |
| CNI | 待填写 |
| 默认 StorageClass | 待填写 |
| Ingress Controller | 待填写 |
| 集群域名/入口域名 | 待填写 |
| 维护负责人 | 待填写 |

## 目录职责

- `infrastructure/networking/`：CNI、地址池、DNS 与网络实验配置。
- `infrastructure/ingress/`：Ingress Controller、入口规则和证书引用。
- `infrastructure/observability/`：指标、日志、链路追踪和测试告警。
- `infrastructure/storage/`：StorageClass、CSI 和存储实验配置。
- `policies/`：Namespace、RBAC、资源配额、NetworkPolicy 和准入策略。
- `apps/`：测试应用与验证工作负载。

## 推荐部署顺序

1. 使用 `bootstrap/kubernetes/` 创建集群。
2. 部署 `infrastructure/networking/` 并验证节点、Pod 和 Service 网络。
3. 应用 `policies/` 中的治理资源。
4. 配置 `infrastructure/storage/`。
5. 配置 `infrastructure/ingress/` 和证书能力。
6. 部署 `infrastructure/observability/`。
7. 部署 `apps/`。

## 实验原则

- 新组件和大版本升级优先在此集群完成验证，再推广至生产环境。
- 实验性配置应注明目的、负责人和清理条件，避免长期遗留。
- 尽可能复用与生产相同的组件版本和资源结构，使验证结果具有参考价值。
- 破坏性测试前确认工作负载和数据允许被重建，并记录恢复步骤。

## 验证记录模板

```text
变更内容：
目标版本：
验证日期：
验证人：
测试范围：
验证结果：
已知问题：
回滚方法：
是否可推广至生产：
```

## 部署前检查

- [ ] 已确认目标 kube-context 为实验集群。
- [ ] 已记录实验目标、成功标准和清理方式。
- [ ] 最终清单可以成功渲染。
- [ ] Secret 仅通过受控方案引用或生成。
- [ ] 已验证节点、网络、存储、入口及核心监控指标。
