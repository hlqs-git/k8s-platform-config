# Alertmanager

负责监控告警的聚合、抑制、路由和通知。

## 配置边界

- `base/`：公共部署资源、路由骨架或公共 Helm values。
- 接收者、通知凭据引用和集群差异放在 `clusters/<cluster>/infrastructure/observability/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、Prometheus 依赖、升级步骤、验证方法和回滚方法。
