# Prometheus

负责指标采集、存储和查询。

## 配置边界

- `base/`：公共部署资源、规则或公共 Helm values。
- 数据保留、存储、采集目标和集群差异放在 `clusters/<cluster>/infrastructure/observability/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、存储依赖、升级步骤、验证方法和回滚方法。
