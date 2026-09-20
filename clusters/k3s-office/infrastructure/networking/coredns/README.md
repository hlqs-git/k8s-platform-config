# k3s-office CoreDNS

Longhorn 建议 CoreDNS 至少运行两个副本，以降低单个 DNS Pod 中断对集群存储组件的影响。

K3s 直接管理 CoreDNS Deployment。本仓库只记录当前副本设置和验证步骤，不提交一个可能与 K3s 管理字段冲突的不完整 Deployment 清单。

## 设置副本数

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl config current-context

kubectl scale deployment coredns \
  --namespace kube-system \
  --replicas=2

kubectl rollout status deployment/coredns --namespace kube-system
```

## 验证

```bash
kubectl get deployment coredns --namespace kube-system
kubectl get pods \
  --namespace kube-system \
  --selector k8s-app=kube-dns \
  -o wide
```

期望 Deployment 为 `2/2`，两个 Pod 都 Ready，并尽量分布在不同节点。K3s 升级后应重新检查副本数。

参考：https://longhorn.io/docs/1.12.1/best-practices/
