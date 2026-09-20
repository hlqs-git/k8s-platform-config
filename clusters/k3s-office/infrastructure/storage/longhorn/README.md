# k3s-office Longhorn

本目录记录 `k3s-office` 三节点集群的 Longhorn 安装参数、节点前置条件和存储读写验收流程。

## 当前配置

| 项目 | 值 |
| --- | --- |
| Helm release / namespace | `longhorn` / `longhorn-system` |
| Chart / version | `longhorn/longhorn` / `1.12.1` |
| 数据引擎 | V1 开启，V2 关闭 |
| 数据目录 | 每个节点的 `/var/lib/longhorn` |
| 底层存储 | 独立 ext4 文件系统，当前由 `/dev/sdb1` 挂载 |
| 默认副本数 | 2 |
| 默认 StorageClass | `longhorn` |
| 数据本地性 | `disabled` |
| 回收策略 | `Delete` |

2 副本是空间利用率、性能和节点故障容忍之间的选择。它不能替代异地备份；重要数据必须另行配置 Longhorn Backup Target 和恢复演练。

## 节点前置条件

在三个节点分别运行：

```bash
sudo bash scripts/validate/longhorn-node-preflight.sh
```

每个节点必须满足：

- 安装 `open-iscsi`、`nfs-common`、`cryptsetup` 和 `dmsetup`。
- `iscsid` 正常运行。
- 独立磁盘以 ext4 挂载到 `/var/lib/longhorn`，并通过文件系统 UUID 写入 `/etc/fstab`。
- 加载 `dm_crypt`，并写入 `/etc/modules-load.d/longhorn.conf` 持久化。
- multipathd 已停止，或配置为不会接管 Longhorn 创建的块设备。

安装依赖并持久化 `dm_crypt`：

```bash
apt-get update
apt-get install -y open-iscsi nfs-common cryptsetup dmsetup
systemctl enable --now iscsid

modprobe dm_crypt
echo dm_crypt > /etc/modules-load.d/longhorn.conf
```

如果节点完全不使用 SAN 或多路径设备，可以禁用 multipathd：

```bash
systemctl disable --now multipathd.service multipathd.socket
systemctl mask multipathd.service multipathd.socket
pgrep -a multipathd || echo 'multipathd not running'
```

如果节点依赖多路径存储，不要禁用服务；应按照 Longhorn 官方说明为 Longhorn 设备配置 multipath 黑名单：https://longhorn.io/kb/troubleshooting-volume-with-multipath/

## CoreDNS

安装 Longhorn 前确认 CoreDNS 至少有两个 Ready 副本。操作记录见 [`networking/coredns/README.md`](../../networking/coredns/README.md)。

## Helm 仓库

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm search repo longhorn/longhorn --versions
```

## 渲染检查

`helm lint` 不接受远端 Chart 的 `--version` 参数，使用 `helm template` 固定并检查目标版本：

```bash
helm template longhorn longhorn/longhorn \
  --version 1.12.1 \
  --namespace longhorn-system \
  -f clusters/k3s-office/infrastructure/storage/longhorn/values.yaml \
  > /tmp/longhorn-rendered.yaml
```

确认渲染输出包含 2 副本、V1 Data Engine、数据目录和容量阈值后再部署。

## 安装或升级

K3s 默认的 `local-path` 原本是默认 StorageClass。安装前移除其默认标记，确保集群只有一个默认 StorageClass：

```bash
kubectl annotate storageclass local-path \
  storageclass.kubernetes.io/is-default-class-
```

安装或升级固定版本：

```bash
helm upgrade --install longhorn longhorn/longhorn \
  --version 1.12.1 \
  --namespace longhorn-system \
  --create-namespace \
  -f clusters/k3s-office/infrastructure/storage/longhorn/values.yaml \
  --wait \
  --timeout 15m
```

## 安装后验证

```bash
kubectl get pods --namespace longhorn-system -o wide
kubectl get storageclass
kubectl get nodes.longhorn.io --namespace longhorn-system
```

三个 Longhorn Node 应为 Ready、允许调度且 Schedulable。检查详细条件：

```bash
for node in master01 master02 master03; do
  echo "===== ${node} ====="
  kubectl get nodes.longhorn.io "${node}" \
    --namespace longhorn-system \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status} Reason={.reason} Message={.message}{"\n"}{end}'
done
```

## PVC 读写冒烟测试

测试资源使用独立 Namespace：

```bash
kubectl apply -k clusters/k3s-office/infrastructure/storage/longhorn/smoke-test
kubectl wait pod/longhorn-test \
  --namespace longhorn-smoke-test \
  --for=condition=Ready \
  --timeout=180s

kubectl exec --namespace longhorn-smoke-test longhorn-test -- sh -c '
  set -e
  dd if=/dev/urandom of=/data/test.bin bs=1M count=256
  sync
  sha256sum /data/test.bin | tee /data/test.bin.sha256
  cd /data
  sha256sum -c test.bin.sha256
'
```

测试成功后删除 Namespace；这会同时删除测试 Pod、PVC 和测试数据：

```bash
kubectl delete namespace longhorn-smoke-test
```

## 已知检查项

- 附件中的实测卷使用 2 副本，分别调度到不同节点，挂载后状态为 `attached/healthy`，256 MiB 文件校验通过。
- `Multipathd=False/MultipathdIsRunning` 表示检测到有风险的 multipathd，不表示检查通过。必须在每个节点实际停止进程或配置设备黑名单。
- `KernelModulesLoaded=False/KernelModulesNotLoaded` 表示 `dm_crypt` 未加载。即使当前未使用加密卷，也应补齐模块并重新检查。

## 回滚与卸载

普通升级优先使用 Helm revision 回滚：

```bash
helm history longhorn --namespace longhorn-system
helm rollback longhorn <revision> --namespace longhorn-system --wait --timeout 15m
```

不要把 `helm uninstall` 当作普通回滚。卸载 Longhorn 可能造成数据丢失，必须先迁移或删除所有使用 Longhorn 的工作负载、PV 和 PVC，并遵循官方卸载流程：https://longhorn.io/docs/1.12.1/deploy/uninstall/
