# Secrets 管理规范

此目录只保存 Secret 管理说明、加密规则或不含敏感值的模板，不保存任何明文凭据。

## 存放位置

- 顶层 `secrets/`：仅保存本规范和仓库级加密策略。
- 组件密文或 Secret 引用：放在所属 `components/<component>/` 附近。
- 集群专属密文或 Secret 引用：放在对应 `clusters/<cluster>/infrastructure/`、`policies/` 或 `apps/` 部署单元中。

让 Secret 声明靠近使用方可以保持所有权、评审范围和生命周期一致；无论位于何处，都必须采用受控加密或外部 Secret 引用。

## 禁止提交

- 密码、访问 Token、API Key 和云平台凭据。
- SSH 私钥、TLS 私钥、证书签发私钥。
- 包含客户端证书或 Token 的 kubeconfig。
- 数据库连接串、Registry 登录凭据和备份加密密钥。
- 解密后的 SOPS 文件、临时导出文件或终端输出。
- 仅经过 Base64 编码的 Kubernetes Secret；Base64 不等于加密。

## 推荐方案

项目应选定一种主要方案，并在确定后将具体操作步骤补充到本文档：

1. **SOPS + KMS/age**：加密后的声明可存入 Git，适合声明式和 GitOps 流程。
2. **External Secrets Operator**：Git 只保存外部 Secret 的引用，真实值存放在 Vault 或云密钥服务中。
3. **Sealed Secrets**：Git 保存只能由目标集群控制器解密的密文对象。

生产环境不建议依赖手工创建 Secret 作为长期流程，因为其状态难以审计和复现。

## 可提交内容

- `README.md` 等流程文档。
- 不含真实值的示例，例如 `secret.example.yaml`。
- 加密后的 Secret 文件，但必须确认加密规则覆盖所有敏感字段。
- ExternalSecret、SecretStore 等只包含引用信息的声明；其中也不得嵌入明文凭据。

示例模板应使用明显的占位值：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: example
type: Opaque
stringData:
  username: REPLACE_ME
  password: REPLACE_ME
```

上述模板仅用于说明字段，填入真实值后不得提交。

## 文件命名建议

- 明文示例：`<name>.example.yaml`
- SOPS 密文：`<name>.sops.yaml`
- External Secrets：`external-secret.yaml`、`secret-store.yaml`
- 加密规则：`.sops.yaml`

不要使用 `secret-final.yaml`、`password.txt` 等难以判断保护状态的名称。

## 提交前检查

1. 查看待提交文件列表和差异。
2. 搜索常见私钥头、Token、密码字段和 kubeconfig 字段。
3. 对加密文件确认敏感值已变为密文，而不是只修改了文件名。
4. 确认 `.gitignore` 未被用作唯一防线；已被 Git 跟踪的文件不会因新增忽略规则而自动消失。
5. 在 CI 中启用 Secret 扫描，并将发现结果作为合并阻断条件。

## 本地使用原则

- 临时解密文件只写入受控临时目录，并在使用后安全清理。
- 不在命令行参数、Shell 历史或共享日志中暴露 Secret。
- kubeconfig 使用最小权限，生产访问凭据与实验环境分离。
- 不在 README、Issue、提交信息或截图中粘贴敏感值。

## 泄露处置

一旦敏感信息进入 Git 历史，应立即：

1. 吊销并轮换相关凭据；不要等待历史清理完成。
2. 评估访问日志和影响范围。
3. 从当前版本与 Git 历史中移除敏感数据。
4. 通知受影响的维护者，并记录事件与改进措施。

仅删除当前文件不足以消除泄露，因为敏感值仍可能存在于历史提交、分支、Fork、缓存或 CI 日志中。
