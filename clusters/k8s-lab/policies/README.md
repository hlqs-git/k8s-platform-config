# Kubernetes 用户认证、Group 与 RBAC 权限管理操作指南

> 本文档用于规范 Kubernetes 集群中普通用户的创建、X.509 客户端证书签发、Group 规划、Namespace 隔离、ClusterRole 权限定义、RoleBinding 授权以及 kubeconfig 创建流程。
>
> 本文档同时作为以下场景的标准操作手册：
>
> * 新增 Kubernetes 用户
> * 将用户加入已有部门 / Group
> * 创建新的部门 / Namespace
> * 创建新的开发组、只读组或管理员组
> * 创建新的 ClusterRole
> * 将已有 ClusterRole 授权给新的 Group
> * 创建用户独立 kubeconfig
> * 验证用户实际权限
> * 用户证书续期
> * 用户离职或权限回收
> * 排查 `Forbidden`、CSR、Group 和 RBAC 问题

---

# 1. 当前目录设计

当前 `k8s-lab` 的访问控制相关配置统一维护在：

```text
clusters/k8s-lab/policies/
```

当前目录结构：

```text
policies/
├── README.md
│
├── authentication/
│   └── csr/
│       ├── README.md
│       └── user1.yaml
│
├── namespace/
│   └── team-a/
│       ├── namespace.yaml
│       └── limit-range.yaml
│
└── rbac/
    ├── bindings/
    │   └── team-a-developers.yaml
    │
    └── cluster-roles/
        └── developer.yaml
```

各目录职责：

```text
authentication/
    用户认证相关配置
    当前使用 Kubernetes CSR API + X.509 客户端证书

namespace/
    Namespace 以及 Namespace 级资源治理
    例如：
    - Namespace
    - LimitRange
    - ResourceQuota

rbac/cluster-roles/
    定义“能够做什么”
    例如：
    - developer
    - viewer
    - namespace-admin

rbac/bindings/
    定义“谁在哪个 Namespace 可以使用哪个角色”

README.md
    整个 policies 目录的操作规范
```

必须坚持：

```text
Authentication = 你是谁
Authorization  = 你能做什么
```

不要把二者混在一起。

---

# 2. 整体权限模型

当前推荐模型：

```text
用户
 │
 │ X.509 Certificate
 ▼
Kubernetes Authentication
 │
 ├── CN = username
 │
 └── O  = group
         │
         ▼
       Group
         │
         ▼
    RoleBinding
         │
         ▼
    ClusterRole
         │
         ▼
     Namespace
```

例如当前 `user1`：

```text
user1.crt
│
├── CN=user1
│
└── O=team-a-developers
        │
        ▼
Group:
team-a-developers
        │
        ▼
RoleBinding:
team-a-developers
namespace: team-a
        │
        ▼
ClusterRole:
developer
        │
        ▼
可操作：
team-a Namespace
```

最终：

```text
user1

可以：
team-a 中创建 Pod
team-a 中创建 Deployment
team-a 中创建 Service
team-a 中查看日志
team-a 中 exec Pod
...

不能：
访问 kube-system
访问其他 Team Namespace
获取 Nodes
修改 ClusterRole
修改 Namespace
执行集群级管理员操作
```

---

# 3. 必须先理解的核心概念

## 3.1 Linux 用户和 Kubernetes 用户没有关系

例如：

```bash
useradd -m user1
```

创建的是 Linux 操作系统用户。

它存在于：

```text
/etc/passwd
```

而：

```text
CN=user1
```

代表 Kubernetes 用户身份。

二者完全独立。

例如完全可以：

```text
Linux 用户：
linux-user-a

Kubernetes 用户：
alice
```

只要 kubeconfig 中使用 Alice 的证书：

```text
CN=alice
```

Kubernetes 就认为请求者是：

```text
alice
```

而不是 Linux 用户名。

因此：

```text
Linux account != Kubernetes User
```

在实验环境中让两者同名，只是为了方便管理：

```text
Linux:      user1
Kubernetes: user1
```

---

# 4. Kubernetes 普通用户并不是 Kubernetes API 对象

Kubernetes 不存在：

```bash
kubectl get users
```

也不能：

```yaml
apiVersion: ...
kind: User
```

来创建普通用户。

普通用户的身份由外部认证机制提供。

本项目当前使用：

```text
X.509 Client Certificate Authentication
```

也就是说：

```text
有效客户端证书
        ↓
kube-apiserver
        ↓
识别 Username + Groups
```

---

# 5. 私钥、CSR 和证书之间是什么关系

整个过程：

```text
user1.key
私钥
   │
   │ openssl req
   ▼
user1.csr
证书签名请求
   │
   │ Kubernetes CSR API
   │
   │ Administrator Approve
   ▼
Kubernetes CA
   │
   │ 签名
   ▼
user1.crt
客户端证书
```

---

## 5.1 `.key`

例如：

```text
user1.key
```

这是用户私钥。

作用：

```text
证明持有证书的人确实拥有对应私钥
```

安全级别非常高。

任何获得：

```text
user1.key + user1.crt
```

的人，都可以冒充：

```text
user1
```

因此：

```text
*.key
```

绝对禁止：

```text
提交 Git
发送到公开聊天
邮件明文发送
放入共享目录
```

推荐权限：

```bash
chmod 600 user1.key
```

---

# 6. `.csr` 是什么

CSR：

```text
Certificate Signing Request
```

中文：

```text
证书签名请求
```

CSR 本身不是最终证书。

CSR 中主要包含：

```text
用户的公钥

+
申请的身份信息

CN=username
O=group
```

可以理解为：

```text
我要申请一张证书。

我的用户名是 user1。

我属于 team-a-developers。

这是我的公钥。

请 Kubernetes CA 为我签名。
```

---

# 7. CN 和 O 的含义

创建 CSR：

```bash
openssl req \
  -new \
  -key user1.key \
  -out user1.csr \
  -subj "/CN=user1/O=team-a-developers"
```

这里最关键的是：

```text
CN = Common Name
O  = Organization
```

Kubernetes X.509 客户端认证使用：

```text
CN → Username

O  → Group
```

因此：

```text
CN=user1
```

代表：

```text
Username = user1
```

而：

```text
O=team-a-developers
```

代表：

```text
Group = team-a-developers
```

---

# 8. Group 并不是 Kubernetes 对象

不存在：

```bash
kubectl get groups
```

也不需要创建：

```yaml
kind: Group
```

Group 实际只是认证系统提供给 Kubernetes 的字符串：

```text
team-a-developers
```

证书：

```text
O=team-a-developers
```

认证后：

```text
Groups:
  team-a-developers
```

RoleBinding：

```yaml
subjects:
  - kind: Group
    name: team-a-developers
```

只要名字匹配：

```text
证书 O
        │
        ▼
team-a-developers
        │
        │ exact match
        ▼
RoleBinding subject
        │
        ▼
team-a-developers
```

权限就可以匹配。

建议所有 Group：

```text
全小写
使用 -
名称统一
不要混用大小写
```

例如：

```text
team-a-developers
team-a-viewers
team-a-admins

team-b-developers
team-b-viewers
```

---

# 9. 一个用户可以属于多个 Group

例如：

```bash
openssl req \
  -new \
  -key user1.key \
  -out user1.csr \
  -subj "/CN=user1/O=team-a-developers/O=monitoring-viewers"
```

认证后相当于：

```text
Username:
  user1

Groups:
  team-a-developers
  monitoring-viewers
```

这样就可以通过不同 RoleBinding 获得不同权限。

---

# 10. Role、ClusterRole、RoleBinding 和 ClusterRoleBinding

这是 RBAC 中最容易混淆的地方。

## Role

Role：

```text
Namespace Scoped
```

定义某一个 Namespace 中的权限。

---

## ClusterRole

ClusterRole 本身是：

```text
Cluster Scoped Object
```

但是：

```text
ClusterRole
```

并不等于：

```text
权限一定是集群级
```

关键取决于它如何绑定。

---

## RoleBinding + ClusterRole

当前采用：

```text
ClusterRole
     ↓
RoleBinding
     ↓
Namespace
```

例如：

```yaml
kind: RoleBinding
metadata:
  namespace: team-a
```

引用：

```yaml
roleRef:
  kind: ClusterRole
  name: developer
```

最终：

```text
developer 的 namespaced 权限
只在 team-a 生效
```

这是当前推荐设计。

---

## ClusterRoleBinding

如果使用：

```yaml
kind: ClusterRoleBinding
```

则 ClusterRole 权限会被授予：

```text
整个 Cluster
```

例如：

```text
所有 Namespace
```

所以：

```text
普通部门开发用户：

推荐：
RoleBinding + ClusterRole

不要：
ClusterRoleBinding + ClusterRole
```

除非明确需要集群级权限。

---

# 11. 标准场景一：创建一个新用户

下面以：

```text
用户：
user1

部门：
team-a

Group：
team-a-developers

ClusterRole：
developer

Namespace：
team-a
```

为完整示例。

---

# 12. Step 1：可选——创建 Linux 用户

如果用户直接登录 Kubernetes Master 或运维跳板机，可以创建 Linux 用户：

```bash
useradd -m user1
```

或者：

```bash
adduser user1
```

不要直接编辑：

```text
/etc/passwd
```

验证：

```bash
id user1
```

然后：

```bash
su - user1
```

创建 kube 目录：

```bash
mkdir -p ~/.kube
chmod 700 ~/.kube
```

注意：

Linux 用户只是操作系统账号。

这一步不是 Kubernetes 创建用户的必要步骤。

如果用户在自己的电脑使用 kubectl，则完全不需要在 Kubernetes Master 上创建 Linux 用户。

---

# 13. Step 2：用户自己生成私钥

推荐由用户本人生成私钥。

```bash
cd ~/.kube
```

执行：

```bash
openssl genrsa -out user1.key 3072
```

设置权限：

```bash
chmod 600 user1.key
```

检查：

```bash
ls -l user1.key
```

应该类似：

```text
-rw------- user1 user1 user1.key
```

重要原则：

```text
私钥应该始终由用户自己持有。
```

生产环境中管理员原则上不应该要求用户把：

```text
user1.key
```

发送给管理员。

---

# 14. Step 3：生成 CSR 文件

执行：

```bash
openssl req \
  -new \
  -key user1.key \
  -out user1.csr \
  -subj "/CN=user1/O=team-a-developers"
```

得到：

```text
user1.csr
```

检查：

```bash
openssl req \
  -in user1.csr \
  -noout \
  -subject
```

必须看到：

```text
subject=CN = user1, O = team-a-developers
```

如果 Group 写错：

```text
team-a-developer
```

而 RoleBinding 是：

```text
team-a-developers
```

则不会匹配。

因此这里必须仔细确认。

---

# 15. Step 4：将 CSR Base64 编码

Kubernetes CSR API 的：

```yaml
spec:
  request:
```

要求 CSR 内容进行 Base64 编码。

Ubuntu/Linux：

```bash
base64 -w 0 user1.csr
```

输出类似：

```text
LS0tLS1CRUdJTiBDRVJUSUZJQ0FURSBSRVFVRVNULS0...
```

也可以使用：

```bash
base64 < user1.csr | tr -d '\n'
```

不要：

```text
Base64 user1.key
```

必须编码：

```text
user1.csr
```

---

# 16. Step 5：创建 Kubernetes CSR YAML

项目位置：

```text
clusters/k8s-lab/policies/authentication/csr/
```

例如：

```text
user1.yaml
```

内容：

```yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest

metadata:
  name: user1

spec:
  request: <BASE64_CSR>

  signerName: kubernetes.io/kube-apiserver-client

  expirationSeconds: 31536000

  usages:
    - client auth
```

其中：

```text
31536000 秒 = 365 天
```

说明：

```yaml
signerName: kubernetes.io/kube-apiserver-client
```

表示：

```text
申请 kube-apiserver 客户端认证证书
```

而：

```yaml
usages:
  - client auth
```

表示：

```text
证书用于客户端身份认证
```

注意：

`expirationSeconds` 是申请时长。

实际证书有效期还受到集群 CA / kube-controller-manager 配置限制。

最终有效期必须用：

```bash
openssl x509 -dates
```

检查，而不是只相信 YAML 中的数字。

---

# 17. 推荐新的 CSR 对象命名方式

CSR API 对象属于一次性签发流程。

长期管理时，不建议所有年份都使用：

```text
metadata.name: user1
```

建议未来使用：

```text
user1-20260916
user1-20270916
```

例如：

```yaml
metadata:
  name: user1-20260916
```

但是证书本身依然可以：

```text
CN=user1
```

注意：

```text
CSR metadata.name
```

和：

```text
Certificate CN
```

不是一回事。

这样做方便：

```text
证书续期
审计
历史跟踪
避免 CSR request 不可修改导致冲突
```

---

# 18. Step 6：管理员应用 CSR

切回管理员：

```bash
exit
```

进入：

```bash
cd clusters/k8s-lab/policies/authentication/csr/
```

先验证：

```bash
kubectl apply \
  --dry-run=server \
  -f user1.yaml
```

确认无错误后：

```bash
kubectl apply -f user1.yaml
```

查看：

```bash
kubectl get csr
```

应该：

```text
NAME    SIGNERNAME                            REQUESTOR           CONDITION
user1   kubernetes.io/kube-apiserver-client   kubernetes-admin   Pending
```

---

# 19. REQUESTOR 为什么是 kubernetes-admin

这里经常产生误解。

例如：

```text
REQUESTOR:
kubernetes-admin
```

不是说最终证书用户是：

```text
kubernetes-admin
```

REQUESTOR 表示：

```text
是谁向 Kubernetes API 创建了这个 CSR 对象
```

真正申请的证书身份在：

```text
spec.request
```

里面。

因此审批 CSR 时不要只看：

```bash
kubectl describe csr user1
```

最重要的是解码真正的 CSR。

---

# 20. Step 7：审批前必须检查证书 Subject

执行：

```bash
kubectl get csr user1 \
  -o jsonpath='{.spec.request}' \
  | base64 -d \
  | openssl req -noout -subject
```

必须看到：

```text
subject=CN = user1, O = team-a-developers
```

管理员必须确认：

```text
Username 是否正确

Group 是否正确

Group 是否真的应该拥有对应权限
```

审批动作本质上是在说：

```text
“我允许 Kubernetes CA 为这个身份签发证书。”
```

所以绝不能：

```bash
kubectl certificate approve
```

而不检查 Subject。

---

# 21. 特别危险的 CSR

如果看到类似：

```text
O=system:masters
```

必须停止审批并调查。

普通用户和普通部门 Group：

```text
不要使用 system: 前缀
```

建议只使用自己规划的：

```text
team-a-developers
team-a-viewers
operations
monitoring-viewers
```

---

# 22. Step 8：管理员批准 CSR

确认无误：

```bash
kubectl certificate approve user1
```

查看：

```bash
kubectl get csr user1
```

应该：

```text
Approved,Issued
```

例如：

```text
NAME    REQUESTEDDURATION   CONDITION
user1   365d                Approved,Issued
```

这意味着：

```text
CSR 已批准

+

Kubernetes CA 已签发证书
```

---

# 23. Step 9：导出用户客户端证书

执行：

```bash
kubectl get csr user1 \
  -o jsonpath='{.status.certificate}' \
  | base64 -d \
  > /home/user1/.kube/user1.crt
```

修正权限：

```bash
chown user1:user1 /home/user1/.kube/user1.crt
chmod 644 /home/user1/.kube/user1.crt
```

检查：

```bash
openssl x509 \
  -in /home/user1/.kube/user1.crt \
  -noout \
  -subject \
  -issuer \
  -dates
```

应该类似：

```text
subject=O = team-a-developers, CN = user1

issuer=CN = kubernetes

notBefore=...
notAfter=...
```

最关键的是：

```text
CN=user1
O=team-a-developers
```

---

# 24. 此时认证链路已经形成

```text
user1.key
       +
user1.crt
       │
       ▼
kube-apiserver
       │
       ▼
证书由可信 Kubernetes CA 签名？
       │
      YES
       │
       ▼
CN=user1
       │
       ▼
Username=user1

O=team-a-developers
       │
       ▼
Group=team-a-developers
```

但：

```text
认证成功
```

并不代表：

```text
有权限操作 Kubernetes
```

接下来由 RBAC 决定。

---

# 25. Step 10：定义 ClusterRole

项目路径：

```text
policies/rbac/cluster-roles/
```

例如：

```text
developer.yaml
```

推荐 Developer 模板：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole

metadata:
  name: developer
  labels:
    managed-by: gitops

rules:

  # ---------------------------------------------------
  # Core resources
  # ---------------------------------------------------

  - apiGroups: [""]
    resources:
      - pods
      - services
      - configmaps
      - persistentvolumeclaims
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

  # ---------------------------------------------------
  # Pod logs
  # ---------------------------------------------------

  - apiGroups: [""]
    resources:
      - pods/log
    verbs:
      - get

  # ---------------------------------------------------
  # Interactive Pod operations
  # ---------------------------------------------------

  - apiGroups: [""]
    resources:
      - pods/exec
      - pods/portforward
    verbs:
      - create

  # ---------------------------------------------------
  # Events
  # ---------------------------------------------------

  - apiGroups: [""]
    resources:
      - events
    verbs:
      - get
      - list
      - watch

  # ---------------------------------------------------
  # Application workloads
  # ---------------------------------------------------

  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

  # ---------------------------------------------------
  # Scale subresources
  # Allows kubectl scale
  # ---------------------------------------------------

  - apiGroups: ["apps"]
    resources:
      - deployments/scale
      - replicasets/scale
      - statefulsets/scale
    verbs:
      - get
      - update
      - patch

  # ---------------------------------------------------
  # Batch workloads
  # ---------------------------------------------------

  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

  # ---------------------------------------------------
  # HPA
  # ---------------------------------------------------

  - apiGroups: ["autoscaling"]
    resources:
      - horizontalpodautoscalers
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

  # ---------------------------------------------------
  # Legacy resources required by some kubectl get all
  # ---------------------------------------------------

  - apiGroups: [""]
    resources:
      - replicationcontrollers
    verbs:
      - get
      - list
      - watch
```

---

# 26. API Group 必须写正确

之前最容易出现的错误之一是：

```yaml
apiGroups: [""]
resources:
  - jobs
  - cronjobs
```

这是错误的。

正确：

```yaml
apiGroups: ["batch"]
resources:
  - jobs
  - cronjobs
```

常见 API Group：

```text
Resource                    API Group

pods                        ""
services                    ""
configmaps                   ""
secrets                     ""
persistentvolumeclaims      ""
events                      ""

deployments                 apps
replicasets                 apps
statefulsets                apps
daemonsets                  apps

jobs                        batch
cronjobs                    batch

horizontalpodautoscalers    autoscaling

ingresses                   networking.k8s.io
networkpolicies             networking.k8s.io

poddisruptionbudgets        policy

roles                       rbac.authorization.k8s.io
rolebindings                rbac.authorization.k8s.io
clusterroles                rbac.authorization.k8s.io
clusterrolebindings         rbac.authorization.k8s.io
```

不要靠记忆猜。

应该使用 Kubernetes API 查询：

```bash
kubectl api-resources
```

例如：

```bash
kubectl api-resources | grep -E 'jobs|cronjobs'
```

或者：

```bash
kubectl api-resources --api-group=batch
```

查询 apps：

```bash
kubectl api-resources --api-group=apps
```

查看支持哪些 verbs：

```bash
kubectl api-resources -o wide
```

创建 ClusterRole 前先确认：

```text
Resource
API Group
Namespaced
Verbs
```

---

# 27. Kubernetes RBAC verbs

常见 verbs：

```text
get
    获取单个资源

list
    获取资源列表

watch
    持续监听资源变化

create
    创建资源

update
    更新完整资源

patch
    局部修改

delete
    删除资源
```

只读角色一般：

```yaml
verbs:
  - get
  - list
  - watch
```

开发角色通常：

```yaml
verbs:
  - get
  - list
  - watch
  - create
  - update
  - patch
  - delete
```

必须坚持：

```text
Least Privilege
最小权限原则
```

不要因为：

```text
“以后可能有用”
```

就提前开放权限。

---

# 28. 为什么 pods/exec 单独处理

`pods/exec`：

```bash
kubectl exec -it pod -- bash
```

它属于：

```text
Pod subresource
```

推荐：

```yaml
- apiGroups: [""]
  resources:
    - pods/exec
  verbs:
    - create
```

而不是随便给所有 verbs。

同样：

```text
pods/portforward
```

通常只需要：

```text
create
```

---

# 29. Secret 权限的重要安全说明

推荐 Developer ClusterRole 不直接添加：

```yaml
resources:
  - secrets
```

因为：

```text
get secrets
list secrets
watch secrets
```

都可能让用户获取 Secret 内容。

但必须注意一个更加重要的事实：

如果用户拥有：

```text
create pods

或者：

create deployments
create statefulsets
create daemonsets
```

那么该用户通常可以创建工作负载并将同 Namespace 中的 Secret：

```text
挂载为 Volume

或者

引用为环境变量
```

因此：

```text
“禁止 get secrets”
```

并不代表：

```text
“这个用户完全无法获取 Namespace 中的 Secret”
```

只要用户拥有自由创建工作负载的权限，就必须把这个用户视为：

```text
对该 Namespace 具有较高信任级别
```

因此真正的安全隔离边界应该是：

```text
不同信任级别
        ↓
不同 Namespace
```

敏感应用不要和普通开发应用混在同一个 Namespace。

生产环境还应该结合：

```text
Pod Security Admission
NetworkPolicy
独立 ServiceAccount
Admission Policy
Secret 管理系统
```

进一步限制。

---

# 30. Step 11：创建 Group RoleBinding

当前：

```text
team-a-developers
```

应该创建：

```text
policies/rbac/bindings/team-a-developers.yaml
```

内容：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding

metadata:
  name: team-a-developers
  namespace: team-a
  labels:
    managed-by: gitops

subjects:

  - kind: Group
    name: team-a-developers
    apiGroup: rbac.authorization.k8s.io

roleRef:

  apiGroup: rbac.authorization.k8s.io

  kind: ClusterRole

  name: developer
```

核心关系：

```text
Group:
team-a-developers
        │
        ▼
RoleBinding:
namespace=team-a
        │
        ▼
ClusterRole:
developer
```

---

# 31. RoleBinding 必须特别检查 namespace

最重要：

```yaml
metadata:
  namespace: team-a
```

如果误写：

```yaml
namespace: team-b
```

那么权限就被授权到了：

```text
team-b
```

而不是 team-a。

所以所有 RoleBinding 必须检查：

```text
subjects.name
metadata.namespace
roleRef.name
```

这三个字段。

---

# 32. Step 12：应用 RBAC

先 server-side dry run：

```bash
kubectl apply \
  --dry-run=server \
  -f rbac/cluster-roles/developer.yaml
```

然后：

```bash
kubectl apply \
  -f rbac/cluster-roles/developer.yaml
```

验证：

```bash
kubectl get clusterrole developer
```

查看：

```bash
kubectl get clusterrole developer -o yaml
```

RoleBinding：

```bash
kubectl apply \
  --dry-run=server \
  -f rbac/bindings/team-a-developers.yaml
```

然后：

```bash
kubectl apply \
  -f rbac/bindings/team-a-developers.yaml
```

检查：

```bash
kubectl get rolebinding \
  -n team-a
```

详细：

```bash
kubectl get rolebinding \
  team-a-developers \
  -n team-a \
  -o yaml
```

---

# 33. Step 13：创建用户独立 kubeconfig

用户已经拥有：

```text
user1.key
user1.crt
```

接下来创建：

```text
/home/user1/.kube/config
```

管理员定义：

```bash
K8S_USER=user1

K8S_GROUP=team-a-developers

NAMESPACE=team-a

CLUSTER_ALIAS=k8s-lab

KUBECONFIG_USER=/home/${K8S_USER}/.kube/config

ADMIN_KUBECONFIG=/etc/kubernetes/admin.conf
```

获取 API Server：

```bash
SERVER=$(
  kubectl \
    --kubeconfig="${ADMIN_KUBECONFIG}" \
    config view \
    --minify \
    -o jsonpath='{.clusters[0].cluster.server}'
)
```

检查：

```bash
echo "${SERVER}"
```

例如实验集群：

```text
https://192.168.12.81:6443
```

生产 HA 集群建议使用：

```text
VIP
LoadBalancer
API Server FQDN
```

而不是绑定某一个 Master IP。

---

# 34. 配置 Cluster

kubeadm 集群一般 CA：

```text
/etc/kubernetes/pki/ca.crt
```

执行：

```bash
kubectl config set-cluster "${CLUSTER_ALIAS}" \
  --server="${SERVER}" \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --kubeconfig="${KUBECONFIG_USER}"
```

这里：

```text
server
```

告诉 kubectl：

```text
API Server 在哪里
```

而：

```text
certificate-authority
```

用于验证：

```text
API Server TLS 证书是否可信
```

不要为了方便使用：

```text
--insecure-skip-tls-verify=true
```

---

# 35. 写入 user1 证书和私钥

执行：

```bash
kubectl config set-credentials "${K8S_USER}" \
  --client-certificate="/home/${K8S_USER}/.kube/${K8S_USER}.crt" \
  --client-key="/home/${K8S_USER}/.kube/${K8S_USER}.key" \
  --embed-certs=true \
  --kubeconfig="${KUBECONFIG_USER}"
```

`--embed-certs=true` 会把证书和私钥嵌入：

```text
kubeconfig
```

因此最终：

```text
~/.kube/config
```

本身就是敏感凭据。

---

# 36. 创建 Context

执行：

```bash
kubectl config set-context \
  "${K8S_USER}@${CLUSTER_ALIAS}" \
  --cluster="${CLUSTER_ALIAS}" \
  --user="${K8S_USER}" \
  --namespace="${NAMESPACE}" \
  --kubeconfig="${KUBECONFIG_USER}"
```

这里指定：

```text
Cluster:
k8s-lab

User:
user1

Default Namespace:
team-a
```

---

# 37. 设置 Current Context

```bash
kubectl config use-context \
  "${K8S_USER}@${CLUSTER_ALIAS}" \
  --kubeconfig="${KUBECONFIG_USER}"
```

修正权限：

```bash
chown -R "${K8S_USER}:${K8S_USER}" \
  "/home/${K8S_USER}/.kube"

chmod 700 \
  "/home/${K8S_USER}/.kube"

chmod 600 \
  "${KUBECONFIG_USER}"
```

---

# 38. kubeconfig 最终逻辑结构

最终类似：

```yaml
apiVersion: v1
kind: Config

clusters:

  - name: k8s-lab

    cluster:

      server: https://192.168.12.81:6443

      certificate-authority-data: ...

users:

  - name: user1

    user:

      client-certificate-data: ...

      client-key-data: ...

contexts:

  - name: user1@k8s-lab

    context:

      cluster: k8s-lab

      user: user1

      namespace: team-a

current-context: user1@k8s-lab
```

注意：

```text
client-key-data
```

就是私钥。

因此：

```text
kubeconfig = credential
```

不能提交 Git。

---

# 39. Step 14：以用户身份验证

切换：

```bash
su - user1
```

查看：

```bash
kubectl config current-context
```

应该：

```text
user1@k8s-lab
```

查看配置：

```bash
kubectl config view
```

注意：

默认会显示：

```text
DATA+OMITTED
```

这是正常的。

不要随便：

```bash
kubectl config view --raw
```

然后把输出贴到公开位置，因为 `--raw` 可能展示敏感凭据。

---

# 40. 权限验证

验证 team-a：

```bash
kubectl auth can-i get pods \
  -n team-a
```

应该：

```text
yes
```

验证 Deployment：

```bash
kubectl auth can-i create deployments \
  -n team-a
```

应该：

```text
yes
```

验证其他 Namespace：

```bash
kubectl auth can-i get pods \
  -n kube-system
```

应该：

```text
no
```

验证 Node：

```bash
kubectl auth can-i get nodes
```

应该：

```text
no
```

验证 Namespace：

```bash
kubectl auth can-i list namespaces
```

应该：

```text
no
```

---

# 41. 查看用户全部 Namespace 权限

非常推荐：

```bash
kubectl auth can-i \
  --list \
  -n team-a
```

这比直接看 ClusterRole 更有意义。

因为它展示的是：

```text
user1 最终实际获得的权限
```

而不仅仅是：

```text
developer.yaml 写了什么
```

---

# 42. 管理员模拟用户权限

管理员不需要切换 user1，也可以测试：

```bash
kubectl auth can-i \
  list pods \
  -n team-a \
  --as=user1 \
  --as-group=team-a-developers
```

应该：

```text
yes
```

测试 kube-system：

```bash
kubectl auth can-i \
  list pods \
  -n kube-system \
  --as=user1 \
  --as-group=team-a-developers
```

应该：

```text
no
```

这种方法非常适合 RBAC 排错。

---

# 43. 为什么 kubectl get all 曾经报 Forbidden

例如：

```bash
kubectl get all -n team-a
```

曾经报：

```text
replicationcontrollers is forbidden

horizontalpodautoscalers.autoscaling is forbidden
```

原因不是：

```text
证书失败
```

也不是：

```text
Group 失败
```

而是：

```text
developer ClusterRole 没有这两种资源的 list 权限
```

添加：

```yaml
- apiGroups: [""]
  resources:
    - replicationcontrollers
  verbs:
    - get
    - list
    - watch
```

和：

```yaml
- apiGroups: ["autoscaling"]
  resources:
    - horizontalpodautoscalers
  verbs:
    - get
    - list
    - watch
```

后：

```bash
kubectl get all -n team-a
```

正常：

```text
No resources found in team-a namespace.
```

---

# 44. kubectl get all 并不是真的“所有资源”

必须注意：

```bash
kubectl get all
```

不是：

```text
获取 Kubernetes 所有 API Resource
```

它只是查询 Kubernetes 标记在：

```text
category=all
```

中的一组常见资源。

因此不要为了：

```text
“让 kubectl get all 不报错”
```

而盲目扩大 RBAC 权限。

权限设计应该根据：

```text
业务实际需要
```

而不是命令是否好看。

如果报：

```text
xxx is forbidden
```

应该：

```text
1. 确认用户是否真的需要该资源
2. 确认资源 API Group
3. 确认需要什么 verb
4. 再决定是否增加权限
```

---

# 45. 标准场景二：创建新的部门 team-b

假设：

```text
部门：
Team B

Namespace：
team-b

开发 Group：
team-b-developers

只读 Group：
team-b-viewers
```

推荐目录：

```text
namespace/
├── team-a/
│
└── team-b/
    ├── namespace.yaml
    ├── limit-range.yaml
    └── resource-quota.yaml
```

---

# 46. 创建 Namespace

```yaml
apiVersion: v1
kind: Namespace

metadata:

  name: team-b

  labels:

    team: team-b

    managed-by: gitops
```

保存：

```text
namespace/team-b/namespace.yaml
```

---

# 47. 创建 LimitRange

例如：

```yaml
apiVersion: v1
kind: LimitRange

metadata:

  name: default-limits

  namespace: team-b

spec:

  limits:

    - type: Container

      default:

        cpu: "1"

        memory: 1Gi

      defaultRequest:

        cpu: 100m

        memory: 128Mi
```

注意：

```yaml
default:
```

不是最大限制。

它表示：

```text
用户没填写 limits 时自动赋予的默认值
```

如果需要最大限制，可以：

```yaml
max:

  cpu: "4"

  memory: 8Gi
```

---

# 48. 可选 ResourceQuota

例如：

```yaml
apiVersion: v1
kind: ResourceQuota

metadata:

  name: team-b-quota

  namespace: team-b

spec:

  hard:

    requests.cpu: "10"

    requests.memory: 20Gi

    limits.cpu: "20"

    limits.memory: 40Gi

    pods: "50"

    services: "20"

    persistentvolumeclaims: "10"
```

数字必须根据实际集群容量决定。

不要直接复制示例值到生产。

---

# 49. Namespace 应先创建

为了避免：

```text
namespace not found
```

建议先：

```bash
kubectl apply \
  -f namespace/team-b/namespace.yaml
```

再：

```bash
kubectl apply \
  -f namespace/team-b/limit-range.yaml
```

和：

```bash
kubectl apply \
  -f namespace/team-b/resource-quota.yaml
```

---

# 50. 为新部门创建 RoleBinding

如果使用已有：

```text
ClusterRole developer
```

不需要重新创建 ClusterRole。

只需要：

```text
team-b-developers.yaml
```

内容：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding

metadata:

  name: team-b-developers

  namespace: team-b

  labels:

    managed-by: gitops

subjects:

  - kind: Group

    name: team-b-developers

    apiGroup: rbac.authorization.k8s.io

roleRef:

  apiGroup: rbac.authorization.k8s.io

  kind: ClusterRole

  name: developer
```

结果：

```text
team-a-developers
        │
        ▼
developer
        │
        ▼
team-a


team-b-developers
        │
        ▼
developer
        │
        ▼
team-b
```

同一个 ClusterRole 被复用。

这是推荐设计。

---

# 51. 为 team-b 创建用户

例如：

```text
user2
```

CSR：

```bash
openssl req \
  -new \
  -key user2.key \
  -out user2.csr \
  -subj "/CN=user2/O=team-b-developers"
```

不用修改：

```text
ClusterRole developer
```

只要：

```text
O=team-b-developers
```

就会匹配：

```text
team-b-developers RoleBinding
```

---

# 52. 标准场景三：创建新的 ClusterRole

不要为了每个部门复制：

```text
developer-team-a
developer-team-b
developer-team-c
```

如果权限相同：

```text
只维护一个：

developer
```

然后通过不同 RoleBinding 控制 Namespace。

只有权限模型不同才创建新 ClusterRole。

例如：

```text
viewer
developer
namespace-operator
monitoring-viewer
```

---

# 53. 创建只读 ClusterRole 示例

例如：

```text
viewer.yaml
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole

metadata:

  name: viewer

  labels:

    managed-by: gitops

rules:

  - apiGroups: [""]

    resources:

      - pods
      - pods/log
      - services
      - configmaps
      - persistentvolumeclaims
      - events

    verbs:

      - get
      - list
      - watch

  - apiGroups: ["apps"]

    resources:

      - deployments
      - replicasets
      - statefulsets
      - daemonsets

    verbs:

      - get
      - list
      - watch

  - apiGroups: ["batch"]

    resources:

      - jobs
      - cronjobs

    verbs:

      - get
      - list
      - watch

  - apiGroups: ["autoscaling"]

    resources:

      - horizontalpodautoscalers

    verbs:

      - get
      - list
      - watch
```

然后：

```text
team-a-viewers
```

绑定：

```text
viewer
```

而：

```text
team-a-developers
```

绑定：

```text
developer
```

---

# 54. 推荐部门权限模型

建议：

```text
Team A

├── team-a-viewers
│       │
│       └── ClusterRole: viewer
│
├── team-a-developers
│       │
│       └── ClusterRole: developer
│
└── team-a-admins
        │
        └── 经过专门设计的管理角色
```

不要轻易让：

```text
team-a-admins
```

绑定：

```text
cluster-admin
```

因为：

```text
cluster-admin
```

是整个 Kubernetes Cluster 的管理员权限，而不是某个 Namespace 管理员。

---

# 55. 一个部门需要多个 Namespace 时

例如：

```text
team-a-dev
team-a-test
team-a-prod
```

可以复用 Group：

```text
team-a-developers
```

创建多个 RoleBinding：

```text
RoleBinding
team-a-dev
   ↓
developer


RoleBinding
team-a-test
   ↓
developer
```

生产：

```text
team-a-prod
```

可以只授予：

```text
viewer
```

这样：

```text
Team A Developer

dev    → developer
test   → developer
prod   → viewer
```

比直接给整个集群权限安全得多。

---

# 56. 新 ClusterRole 的标准设计流程

每次创建 ClusterRole 时按以下顺序：

```text
第一步
明确用户到底需要做什么

第二步
找到对应 Kubernetes Resource

第三步
确认 API Group

第四步
确认 Namespaced 还是 Cluster Scoped

第五步
确认需要哪些 verbs

第六步
编写 YAML

第七步
server dry-run

第八步
apply

第九步
RoleBinding

第十步
kubectl auth can-i 验证
```

---

# 57. 查询资源是否 Namespaced

执行：

```bash
kubectl api-resources
```

重点：

```text
NAMESPACED
```

例如：

```text
pods            true

deployments     true

nodes           false

namespaces      false

clusterroles    false
```

如果：

```text
NAMESPACED=false
```

就必须特别警惕。

因为 RoleBinding 无法把真正的集群级资源变成 Namespace 级资源。

例如：

```text
nodes
namespaces
persistentvolumes
clusterroles
```

这些本身就是 Cluster Scoped。

---

# 58. Git 中允许保存什么

推荐提交：

```text
namespace.yaml

limit-range.yaml

resource-quota.yaml

ClusterRole YAML

RoleBinding YAML

CSR YAML

README

操作脚本
```

CSR：

```text
user1.csr
```

主要包含公钥和身份申请信息，本身不是私钥。

但是通常没有必要直接把原始：

```text
*.csr
*.crt
```

文件长期提交 Git。

推荐 Git 中保留：

```text
CSR API YAML
```

用于审计和过程记录。

---

# 59. Git 中禁止保存什么

绝对禁止：

```text
*.key

带 client-key-data 的 kubeconfig

admin.conf

super-admin.conf

ServiceAccount Token

Bearer Token

云平台密钥

数据库密码

Registry 密码

任何明文 Secret
```

尤其：

```text
~/.kube/config
```

如果里面有：

```yaml
client-key-data:
```

就属于敏感凭据。

---

# 60. 建议 .gitignore

仓库根目录可以：

```gitignore
# Kubernetes credentials

*.key
*.pem

*.kubeconfig

kubeconfig
admin.conf
super-admin.conf

# Environment credentials

.env
.env.*

# Temporary credentials

credentials/

# Temporary files

*.tmp
*.bak

.DS_Store
```

注意：

```text
.gitignore
```

不是 Secret Management。

它只能降低误提交概率。

---

# 61. CSR YAML 与真正 GitOps 的关系

`CertificateSigningRequest` 属于一次性签发资源。

如果以后使用：

```text
Argo CD
Flux
```

自动同步：

```text
authentication/csr/
```

需要非常谨慎。

因为：

```text
CSR 的生命周期
```

和：

```text
Namespace / RBAC 的持续期望状态
```

不同。

推荐：

```text
CSR YAML 可以留在 Git 中用于记录

但不要让 GitOps Controller 无限自动创建和恢复 CSR
```

可以考虑将：

```text
authentication/csr/
```

排除自动同步。

---

# 62. Git Commit 建议

创建用户：

```bash
git commit \
  -m "feat(authentication): add user1 certificate request"
```

新增部门：

```bash
git commit \
  -m "feat(namespace): add team-b namespace policies"
```

新增 RoleBinding：

```bash
git commit \
  -m "feat(rbac): add team-b developer binding"
```

新角色：

```bash
git commit \
  -m "feat(rbac): add viewer cluster role"
```

权限修复：

```bash
git commit \
  -m "fix(rbac): allow developers to list autoscaling resources"
```

目录规范化：

```bash
git commit \
  -m "refactor(namespace): normalize team-a directory name"
```

---

# 63. 用户证书续期

证书有：

```text
notBefore
notAfter
```

查看：

```bash
openssl x509 \
  -in ~/.kube/user1.crt \
  -noout \
  -subject \
  -dates
```

证书过期后必须重新签发。

推荐不要覆盖历史 CSR：

例如：

```text
user1-20260916
user1-20270901
```

重新：

```text
生成 CSR
      ↓
管理员审核
      ↓
approve
      ↓
导出新 crt
      ↓
更新 kubeconfig
```

如果继续使用原私钥，可以基于原：

```text
user1.key
```

生成新的 CSR。

更高安全要求也可以重新生成：

```text
新的 user1.key
```

---

# 64. 修改用户所属 Group

假设：

```text
user1
```

从：

```text
team-a-developers
```

改成：

```text
team-b-developers
```

不能直接修改已经签发的：

```text
user1.crt
```

因为 Group：

```text
O=team-a-developers
```

已经写进证书。

必须重新：

```text
生成 CSR

CN=user1
O=team-b-developers
```

然后签发新证书。

---

# 65. X.509 用户证书的重要限制

客户端证书方案非常适合：

```text
实验环境
小型集群
少量管理员
固定人员
```

但是人员很多时会出现：

```text
证书生命周期管理复杂

Group 写在证书里

人员调组需要重新签证书

用户离职后的单证书吊销并不方便

证书泄露后需要等待过期或采取更大范围措施
```

因此：

```text
生产集群
大量开发人员
人员经常变化
```

更推荐未来接入：

```text
OIDC

Microsoft Entra ID

Keycloak

其他企业 Identity Provider
```

让：

```text
身份
Group
生命周期
```

由外部身份系统统一管理。

当前 X.509 可以作为：

```text
k8s-lab 的标准方案
```

以及：

```text
应急 / 管理员认证方案
```

---

# 66. 用户离职时必须理解的限制

假设：

```text
user1.crt

O=team-a-developers
```

Group 信息已经写进证书。

Kubernetes 本身没有：

```text
kubectl remove user1 from group
```

这种操作。

因此：

```text
不能像 LDAP/AD 一样实时把 user1 从证书 Group 中删除
```

如果直接删除：

```text
team-a-developers RoleBinding
```

会导致：

```text
整个 team-a-developers
```

全部失去权限。

而不是只删除 user1。

这也是大量用户时应该考虑：

```text
OIDC / External Identity Provider
```

的重要原因。

---

# 67. 证书有效期建议

实验环境：

```text
365d
```

可以接受。

生产用户证书不建议设置过长。

因为证书泄露以后：

```text
证书剩余有效期
```

就是潜在风险窗口。

高安全环境建议：

```text
短期证书
+
自动续期
+
外部 Identity Provider
```

---

# 68. 常见问题：CSR 一直 Pending

执行：

```bash
kubectl get csr
```

如果：

```text
Pending
```

说明：

```text
CSR 已创建
但尚未批准
```

检查 Subject：

```bash
kubectl get csr user1 \
  -o jsonpath='{.spec.request}' \
  | base64 -d \
  | openssl req -noout -subject
```

确认后：

```bash
kubectl certificate approve user1
```

---

# 69. 常见问题：Approved 但没有 Issued

如果：

```text
Approved
```

但长时间没有：

```text
Issued
```

检查：

```bash
kubectl describe csr user1
```

然后检查：

```text
kube-controller-manager

cluster signing CA

cluster signing key
```

是否正常。

---

# 70. 常见问题：Unauthorized

如果看到：

```text
Unauthorized
```

优先检查：

```text
证书是否有效

证书是否过期

CA 是否正确

kubeconfig 是否引用正确证书

client-key 是否匹配证书
```

检查：

```bash
openssl x509 \
  -in user1.crt \
  -noout \
  -subject \
  -issuer \
  -dates
```

---

# 71. 常见问题：Forbidden

例如：

```text
Error from server (Forbidden)
```

通常说明：

```text
Authentication 成功

但是 Authorization 失败
```

换句话说：

```text
Kubernetes 已经知道你是谁

但是 RBAC 不允许这个操作
```

检查：

```bash
kubectl auth can-i ...
```

例如：

```bash
kubectl auth can-i \
  list pods \
  -n team-a
```

---

# 72. Forbidden 标准排错流程

假设：

```text
horizontalpodautoscalers.autoscaling is forbidden
```

第一步：

```bash
kubectl auth can-i \
  list horizontalpodautoscalers \
  -n team-a
```

如果：

```text
no
```

第二步确认资源：

```bash
kubectl api-resources \
  | grep horizontal
```

确认：

```text
API Group = autoscaling
```

第三步检查 ClusterRole：

```bash
kubectl get clusterrole \
  developer \
  -o yaml
```

第四步增加：

```yaml
- apiGroups: ["autoscaling"]

  resources:

    - horizontalpodautoscalers

  verbs:

    - get
    - list
    - watch
```

第五步：

```bash
kubectl apply \
  -f developer.yaml
```

第六步：

```bash
kubectl auth can-i \
  list horizontalpodautoscalers \
  -n team-a
```

应该：

```text
yes
```

---

# 73. 常见问题：RoleBinding 存在，但还是没有权限

检查：

```bash
kubectl get rolebinding \
  team-a-developers \
  -n team-a \
  -o yaml
```

必须确认：

```yaml
subjects:

  - kind: Group

    name: team-a-developers
```

然后检查证书：

```bash
openssl x509 \
  -in ~/.kube/user1.crt \
  -noout \
  -subject
```

必须：

```text
O = team-a-developers
```

如果：

```text
RoleBinding:
team-a-developers

Certificate:
team-a-developer
```

不会匹配。

---

# 74. 常见问题：kubectl get ns Forbidden

例如：

```bash
kubectl get ns
```

返回：

```text
namespaces is forbidden
```

对于普通 Namespace Developer：

```text
这是正常结果。
```

因为：

```text
Namespace
```

本身是 Cluster Scoped Resource。

一个：

```text
team-a developer
```

通常不应该获得：

```text
list namespaces
```

权限。

不要为了消除错误而随便增加权限。

---

# 75. 常见问题：kubectl get nodes Forbidden

例如：

```bash
kubectl get nodes
```

返回：

```text
Forbidden
```

对于普通开发人员：

```text
也是正常结果。
```

Node：

```text
Cluster Scoped Resource
```

普通 Namespace Developer 一般不需要访问。

---

# 76. 常见问题：修改 ClusterRole 后是否需要重新签证书

不需要。

例如：

```text
developer ClusterRole
```

增加：

```text
horizontalpodautoscalers
```

只需要：

```bash
kubectl apply -f developer.yaml
```

RBAC 会立即生效。

不需要：

```text
重新生成 user1.key
重新生成 CSR
重新签发 user1.crt
重新创建 kubeconfig
```

因为：

```text
证书决定身份

RBAC 决定权限
```

二者独立。

---

# 77. 什么时候需要重新签证书

以下情况需要：

```text
证书即将过期

Username 改变

Group 改变

私钥泄露

希望轮换私钥

证书损坏
```

而：

```text
Role 修改

RoleBinding 修改

Namespace 权限修改
```

通常不需要重新签发证书。

---

# 78. 当前推荐部门和权限设计

建议未来统一：

```text
Cluster
│
├── team-a
│   ├── team-a-viewers
│   │       └── viewer
│   │
│   └── team-a-developers
│           └── developer
│
├── team-b
│   ├── team-b-viewers
│   │       └── viewer
│   │
│   └── team-b-developers
│           └── developer
│
└── team-c
    ├── team-c-viewers
    │       └── viewer
    │
    └── team-c-developers
            └── developer
```

ClusterRole：

```text
复用
```

RoleBinding：

```text
按 Namespace 创建
```

这样最容易维护。

---

# 79. 新增用户的快速检查清单

创建新用户时逐项确认：

```text
[ ] 确定 Username

[ ] 确定 Department / Team

[ ] 确定 Group

[ ] 确定目标 Namespace

[ ] 确定 ClusterRole

[ ] 用户生成 Private Key

[ ] chmod 600 Private Key

[ ] 生成 CSR

[ ] 检查 CN

[ ] 检查 O

[ ] CSR Base64

[ ] 创建 CertificateSigningRequest YAML

[ ] kubectl dry-run

[ ] kubectl apply

[ ] 管理员解码 CSR 检查 Subject

[ ] 管理员 approve

[ ] 确认 Approved,Issued

[ ] 导出 crt

[ ] 检查 crt Subject

[ ] 检查 crt issuer

[ ] 检查 crt expiration

[ ] 创建 kubeconfig

[ ] 配置 Cluster CA

[ ] 配置 client certificate

[ ] 配置 client key

[ ] 配置默认 Namespace

[ ] chmod 600 kubeconfig

[ ] kubectl auth can-i 验证允许权限

[ ] kubectl auth can-i 验证禁止权限

[ ] 不提交 key

[ ] 不提交 kubeconfig
```

---

# 80. 新增部门的快速检查清单

```text
[ ] 确定 Namespace 名称

[ ] 全部使用小写

[ ] 创建 namespace.yaml

[ ] 创建 LimitRange

[ ] 根据需要创建 ResourceQuota

[ ] 创建 developers Group 名称

[ ] 创建 viewers Group 名称

[ ] 复用现有 ClusterRole

[ ] 创建 RoleBinding

[ ] 检查 RoleBinding namespace

[ ] 检查 RoleBinding subject

[ ] 检查 roleRef

[ ] dry-run

[ ] apply Namespace

[ ] apply Resource Policies

[ ] apply RoleBinding

[ ] 使用 --as 模拟权限

[ ] 创建真实测试用户验证
```

---

# 81. 新增 ClusterRole 的快速检查清单

```text
[ ] 明确业务需求

[ ] 确认 Resource

[ ] kubectl api-resources 确认 API Group

[ ] 确认 Namespaced / Cluster Scoped

[ ] 确认 verbs

[ ] 遵循 Least Privilege

[ ] 谨慎处理 secrets

[ ] 谨慎处理 pods/exec

[ ] 谨慎处理 workloads create

[ ] 谨慎处理 RBAC resources

[ ] 不授予 escalate

[ ] 不授予 bind

[ ] 谨慎使用 impersonate

[ ] 不随便使用 cluster-admin

[ ] server dry-run

[ ] apply

[ ] kubectl auth can-i

[ ] 验证正向权限

[ ] 验证反向权限
```

---

# 82. 每次授权都必须同时做正向和反向测试

不要只测试：

```text
应该允许的操作
```

还必须测试：

```text
应该禁止的操作
```

例如：

```bash
kubectl auth can-i \
  get pods \
  -n team-a
```

应该：

```text
yes
```

然后：

```bash
kubectl auth can-i \
  get pods \
  -n kube-system
```

应该：

```text
no
```

再：

```bash
kubectl auth can-i \
  get nodes
```

应该：

```text
no
```

再：

```bash
kubectl auth can-i \
  list namespaces
```

应该：

```text
no
```

权限验证必须是：

```text
允许的确实允许

+

不允许的确实禁止
```

---

# 83. 当前 user1 完整验证结果

当前测试已经验证：

```text
user1

Certificate:
CN=user1

Group:
team-a-developers

RoleBinding:
team-a-developers

ClusterRole:
developer

Namespace:
team-a
```

验证：

```text
get pods team-a
YES

create deployments team-a
YES

list replicationcontrollers team-a
YES

list horizontalpodautoscalers team-a
YES

kubectl get all team-a
YES

get pods kube-system
NO

get nodes
NO

list namespaces
NO
```

因此当前认证与 RBAC 链路已经验证成功。

---

# 84. 最终标准架构

```text
                        Kubernetes CA
                             │
                             │ Sign
                             ▼
                       user1.crt
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
          CN=user1              O=team-a-developers
              │                             │
              ▼                             ▼
         Username=user1           Group=team-a-developers
              │                             │
              └──────────────┬──────────────┘
                             │
                             ▼
                       Authentication
                             │
                             ▼
                         Authorized?
                             │
                             ▼
                        RoleBinding
                             │
                   Namespace = team-a
                             │
                             ▼
                       ClusterRole
                         developer
                             │
                             ▼
                      Kubernetes API
```

---

# 85. 最终管理原则

整个用户和权限管理需要始终遵守下面几个原则：

```text
身份和权限分离

用户绑定 Group，不直接大量绑定 User

ClusterRole 定义能力

RoleBinding 定义作用范围

部门通过 Namespace 隔离

不同部门尽量复用 ClusterRole

权限遵循 Least Privilege

所有权限都必须验证正向和反向结果

私钥绝不进入 Git

kubeconfig 按敏感凭据管理

CSR 审批前必须检查 CN/O

普通用户不得使用 system:* 高权限 Group

不要为了消除 Forbidden 而盲目加权限

创建工作负载本身就是较高权限

生产大量用户优先考虑外部 Identity Provider
```

---

# 86. 官方文档参考方向

如需进一步确认行为，应优先参考 Kubernetes 官方文档中的：

```text
Authenticating

Issue a Certificate for a Kubernetes API Client Using a CertificateSigningRequest

Certificates and Certificate Signing Requests

Using RBAC Authorization

Role Based Access Control Good Practices

Organizing Cluster Access Using kubeconfig Files

PKI certificates and requirements
```

本文档中的认证与 RBAC 模型应以当前集群实际 Kubernetes 版本和 Kubernetes 官方文档为最终依据。

---

# 87. 一句话记忆整个过程

创建用户：

```text
Private Key
    ↓
CSR
    ↓
CN = User
O  = Group
    ↓
Kubernetes CSR
    ↓
Admin Review
    ↓
Approve
    ↓
Certificate
    ↓
kubeconfig
    ↓
Authentication
    ↓
Group
    ↓
RoleBinding
    ↓
ClusterRole
    ↓
Namespace Permission
```

创建新部门：

```text
Namespace
    ↓
LimitRange / ResourceQuota
    ↓
Group
    ↓
RoleBinding
    ↓
复用 ClusterRole
```

创建新权限：

```text
业务需求
    ↓
kubectl api-resources
    ↓
Resource + API Group
    ↓
Verbs
    ↓
ClusterRole
    ↓
RoleBinding
    ↓
kubectl auth can-i
```

这三条链路就是本项目 Kubernetes 用户、部门与 RBAC 权限管理的核心。
