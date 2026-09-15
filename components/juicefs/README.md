# JuiceFS

提供面向 Kubernetes 工作负载的分布式文件存储能力。

## 配置边界

- `base/`：公共 CSI 资源或公共 Helm values。
- 元数据服务、对象存储凭据引用、StorageClass 和集群差异放在 `clusters/<cluster>/infrastructure/storage/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、外部存储依赖、升级步骤、恢复验证和回滚方法。
