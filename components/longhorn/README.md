# Longhorn

为 Kubernetes 提供分布式块存储、CSI 动态供给、快照和卷副本能力。

## 配置边界

- `base/`：预留公共资源或公共 Helm values；当前实际参数由集群目录维护。
- 磁盘路径、副本数、StorageClass 和集群差异放在 `clusters/<cluster>/infrastructure/storage/longhorn/`。
- 节点操作系统前置条件通过 `scripts/validate/longhorn-node-preflight.sh` 检查。

## Helm Chart 仓库

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm search repo longhorn/longhorn --versions
```

部署时必须固定 Chart 版本，不直接使用仓库中的浮动最新版本。`k3s-office` 的实际配置见 [`clusters/k3s-office/infrastructure/storage/longhorn/`](../../clusters/k3s-office/infrastructure/storage/longhorn/)。

上游文档：https://longhorn.io/docs/
