# Harbor

提供容器镜像存储、分发与治理能力。

## 配置边界

- `base/`：公共部署资源或公共 Helm values。
- 域名、存储、证书和凭据引用等差异放在目标集群的 `infrastructure/registry/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、数据库与存储依赖、升级步骤、备份验证和回滚方法。
