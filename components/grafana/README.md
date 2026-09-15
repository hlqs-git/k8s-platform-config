# Grafana

提供指标、日志和链路数据的可视化入口。

## 配置边界

- `base/`：公共部署资源、数据源模板或公共 Helm values。
- 域名、数据源凭据引用、持久化和集群差异放在 `clusters/<cluster>/infrastructure/observability/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、依赖、升级步骤、验证方法和回滚方法。
