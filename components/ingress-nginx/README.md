# ingress-nginx

提供基于 NGINX 的 Kubernetes Ingress Controller。

## 配置边界

- `base/`：公共控制器资源或公共 Helm values。
- LoadBalancer 地址、IngressClass、证书引用和集群差异放在 `clusters/<cluster>/infrastructure/ingress/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、兼容性、升级步骤、验证方法和回滚方法。
