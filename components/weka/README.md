# WEKA

提供面向 Kubernetes 工作负载的高性能存储接入能力。

## 配置边界

- `base/`：公共 CSI 资源或公共 Helm values。
- 集群端点、凭据引用、StorageClass 和集群差异放在 `clusters/<cluster>/infrastructure/storage/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、平台依赖、升级步骤、恢复验证和回滚方法。
