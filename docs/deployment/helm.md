# Helm 客户端安装

本文记录在 Debian/Ubuntu 管理节点上通过 Helm 社区维护的 Buildkite APT 仓库安装 Helm CLI 的方法。

## 安装

以下命令需要 root 权限；非 root 用户应在系统修改命令前添加 `sudo`。

```bash
set -euo pipefail

HELM_BUILDKITE_APT_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
HELM_APT_KEY_FILE="$(mktemp)"
trap 'rm -f "${HELM_APT_KEY_FILE}"' EXIT

apt-get update
apt-get install -y curl gpg apt-transport-https
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey -o "${HELM_APT_KEY_FILE}"

ACTUAL_KEY_ID="$(gpg --show-keys --with-colons "${HELM_APT_KEY_FILE}" | awk -F: '$1 == "fpr" {print $10}' | head -n 1)"
if [ "${ACTUAL_KEY_ID}" != "${HELM_BUILDKITE_APT_KEY_ID}" ]; then
  echo "ERROR: unexpected Helm APT key ID: ${ACTUAL_KEY_ID}" >&2
  exit 1
fi

gpg --dearmor < "${HELM_APT_KEY_FILE}" > /usr/share/keyrings/helm.gpg
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
  > /etc/apt/sources.list.d/helm-stable-debian.list

apt-get update
apt-get install -y helm
```

## 验证

```bash
helm version
```

不要把 kubeconfig、仓库凭据或 Helm Registry 密码写入仓库。部署前应显式设置并检查目标 kube-context。

来源：https://helm.sh/docs/intro/install/
