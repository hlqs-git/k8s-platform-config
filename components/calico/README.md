# Calico

提供 Kubernetes 容器网络和网络策略能力。

## 配置边界

- `base/`：公共控制器资源或公共 Helm values。
- Pod CIDR、封装模式、地址池和集群差异放在 `clusters/<cluster>/infrastructure/networking/`。

当前尚未加入实际部署清单，因此不创建空 `kustomization.yaml`。首次引入时必须记录上游来源、固定版本、集群网络前提、升级步骤、验证方法和回滚方法。
