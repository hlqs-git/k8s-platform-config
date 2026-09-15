# Traefik

提供 Kubernetes Ingress 与入口流量管理能力。

## 配置边界

- `base/`：公共控制器资源或公共 Helm values。
- 入口地址、证书引用和集群差异放在 `clusters/<cluster>/infrastructure/ingress/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、CRD 依赖、升级步骤、验证方法和回滚方法。
