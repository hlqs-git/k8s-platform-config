# k3s-office MetalLB

本目录记录 `k3s-office` 集群的 MetalLB 安装参数和 L2 地址发布配置。

## 当前配置

| 项目 | 值 |
| --- | --- |
| Helm release / namespace | `metallb` / `metallb-system` |
| Chart / version | `metallb/metallb` / `0.16.1` |
| 模式 | Native L2（禁用 FRR 与 FRR-K8s） |
| Address pool | `public-ip`：`101.36.148.184/32` |
| 广播接口 | `vlan33` |
| 使用方 | `kube-system/traefik` Service |

公网地址属于基础设施信息，不是认证凭据，但修改前仍应确认网络分配、VLAN 和上游交换网络配置。

## 安装或升级

先按 [`docs/deployment/helm.md`](../../../../../docs/deployment/helm.md) 安装 Helm，并显式确认目标集群：

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl config current-context
kubectl cluster-info

helm repo add metallb https://metallb.github.io/metallb
helm repo update

helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace \
  --version 0.16.1 \
  -f clusters/k3s-office/infrastructure/networking/metallb/values.yaml \
  --wait

kubectl apply -k clusters/k3s-office/infrastructure/networking/metallb
```

不要提交 `/etc/rancher/k3s/k3s.yaml` 或任何派生 kubeconfig。

## 绑定 K3s Traefik

当前 Traefik 由 K3s 管理。以下 annotations 将 LoadBalancer Service 固定到该地址池和公网地址：

```bash
kubectl annotate service traefik \
  --namespace kube-system \
  metallb.io/address-pool=public-ip \
  metallb.io/loadBalancerIPs=101.36.148.184 \
  --overwrite
```

后续将 Traefik 纳入声明式配置时，应把 annotations 迁入 K3s `HelmChartConfig`，避免长期依赖手工修改 Service。

## 验证

```bash
kubectl rollout status deployment/metallb-controller --namespace metallb-system
kubectl get pods --namespace metallb-system -o wide
kubectl get ipaddresspool,l2advertisement --namespace metallb-system
kubectl get service traefik --namespace kube-system
kubectl describe service traefik --namespace kube-system
```

期望 controller 和所有 speaker Pod Ready，`public-l2` 通过 `vlan33` 发布地址池，并且 Traefik 的 `EXTERNAL-IP` 为 `101.36.148.184`。

Traefik 当前使用 `PreferDualStack`，地址池只有 IPv4，因此事件中可能出现无法分配额外地址的提示。只要 IPv4 已分配且服务可达，该提示不影响当前入口；不要为消除提示而添加未经分配的 IPv6 地址。

## 回滚

```bash
helm history metallb --namespace metallb-system
helm rollback metallb <revision> --namespace metallb-system --wait
```

移除地址池或卸载 MetalLB 会中断 Traefik 公网入口，操作前必须准备替代访问路径。
