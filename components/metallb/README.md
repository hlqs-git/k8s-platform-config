# MetalLB

为裸金属 Kubernetes 集群提供 LoadBalancer 服务能力。

## 配置边界

- `base/`：公共控制器资源或公共 Helm values。
- 地址池、L2/BGP 广播和集群网络差异放在 `clusters/<cluster>/infrastructure/networking/`。

当前尚未加入公共部署清单，因此不创建空 `kustomization.yaml`。首次引入公共资源时必须记录上游来源、固定版本、网络依赖、升级步骤、验证方法和回滚方法。

## Helm Chart 仓库

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm search repo metallb/metallb --versions
```

部署时必须在集群配置中固定 Chart 版本。`k3s-office` 的实际安装参数见 [`clusters/k3s-office/infrastructure/networking/metallb/`](../../clusters/k3s-office/infrastructure/networking/metallb/)。

上游安装文档：https://metallb.io/installation/
