# cert-manager

管理集群内证书签发与续期能力。

## 配置边界

- `base/`：公共资源或公共 Helm values。
- 集群 Issuer、域名和环境差异放在 `clusters/<cluster>/infrastructure/ingress/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、CRD 依赖、升级步骤、验证方法和回滚方法。
