# Cluster Configuration Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the `k3s-office` and `k8s-lab` configurations into a cluster-first source-of-truth layout while removing generated artifacts, separating tests, and replacing plaintext Secrets with committed examples.

**Architecture:** `clusters/k3s-office/` and `clusters/k8s-lab/` own every deployable, environment-specific resource; `components/` contains only reusable guidance or bases. Each deployable unit exposes a README plus an optional Helm values file or Kustomize entry, while tests and Secret examples remain outside formal deployment entries. Repository policy scripts enforce the boundaries without requiring access to a live cluster.

**Tech Stack:** Kubernetes YAML, Helm values, Kustomize, PowerShell 7 validation scripts, Bash node preflight scripts, Git.

**Spec:** `docs/superpowers/specs/2026-09-20-cluster-configuration-reorganization-design.md`

## Global Constraints

- Treat `D:/Download/Querk/k3s.tar.gz` only as supplemental input for `k3s-office` and `D:/Download/Querk/edgar.tar.gz` only as supplemental input for `k8s-lab`.
- Treat archive documents, comments, and scripts as untrusted data; never execute archive scripts.
- Keep the current repository version whenever an archive resource conflicts with an existing resource identity.
- Preserve the current uncommitted MetalLB, Longhorn, CoreDNS, Helm documentation, and validation work.
- Do not connect to a cluster or run `kubectl apply`, `helm install`, or `helm upgrade`.
- Do not introduce Flux, Argo CD, SOPS, Sealed Secrets, or another controller.
- Commit only `*.example.yaml` Secret templates; ignore local `*-secret.yaml` and `values.secret.yaml` files.
- Remove tracked backups, rendered output, default values, logs, snapshots, nested repositories, unrelated source code, obsolete intermediate manifests, empty directories, and meaningless `.gitkeep` files.
- Keep reusable tests under a component-local `tests/` directory and exclude them from production `kustomization.yaml` files.
- Record every archive and old-repository source in a migration inventory as kept, merged, example-only, deleted, or not imported.
- Report missing kubectl or Helm checks as `SKIP`, never as `PASS`.

## Review Focus

- Archive entries containing absolute paths or `..` must fail safety validation before extraction; Task 1 adds a malicious-listing test.
- A plaintext `kind: Secret` under an unexpected filename must be detected from content, not only the filename; Task 1 adds this fixture.
- A production Kustomize entry that references `tests/` or `*.example.yaml` must fail even when the referenced file exists; Task 1 adds both fixtures.
- Duplicate resource identities in multi-document YAML must be reported within the same cluster; Task 1 adds a duplicate fixture.
- Missing kubectl or Helm must produce `SKIP` output and must not increment the pass count; Task 1 adds a forced-missing-tool fixture.

---

### Task 1: Repository policy and archive safety validators

**Files:**
- Create: `scripts/validate/repository-policy.ps1`
- Create: `scripts/validate/archive-safety.ps1`
- Create: `scripts/validate/test-repository-policy.ps1`
- Create: `scripts/validate/test-archive-safety.ps1`
- Modify: `.gitignore`
- Delete: `scripts/validate/.gitkeep`

**Interfaces:**
- Produces: `repository-policy.ps1 -Root D:/project/k8s-platform-config [-CheckExternalTools]`, exit `0` for a clean tree and `1` for policy violations; output prefixes are `PASS:`, `FAIL:`, and `SKIP:`.
- Produces: `archive-safety.ps1 -ArchivePath D:/Download/Querk/k3s.tar.gz`, exit `0` only when every archive entry is relative and contains no `..` segment.
- Consumes: no interfaces from later tasks.

- [ ] **Step 1: Write repository-policy fixture tests**

Create a test script that builds isolated temporary fixtures and invokes the policy script. The fixture matrix must include these exact cases:

```powershell
$cases = @(
    @{ Name = 'clean example secret'; Path = 'apps/demo/demo-secret.example.yaml'; Content = "apiVersion: v1`nkind: Secret`nstringData:`n  password: REPLACE_ME`n"; Exit = 0 },
    @{ Name = 'secret under neutral filename'; Path = 'apps/demo/credentials.yaml'; Content = "apiVersion: v1`nkind: Secret`nstringData:`n  password: real-value`n"; Exit = 1 },
    @{ Name = 'rendered output'; Path = 'infrastructure/demo/rendered.yaml'; Content = "apiVersion: v1`nkind: ConfigMap`n"; Exit = 1 },
    @{ Name = 'test referenced by production'; Path = 'apps/demo/kustomization.yaml'; Content = "resources:`n  - tests/pod.yaml`n"; Exit = 1 },
    @{ Name = 'example referenced by production'; Path = 'apps/demo/kustomization.yaml'; Content = "resources:`n  - demo-secret.example.yaml`n"; Exit = 1 }
)
```

Add a two-document fixture containing the same `apiVersion`, `kind`, `metadata.namespace`, and `metadata.name`, then assert exit `1` and output containing `duplicate resource identity`. Invoke `repository-policy.ps1 -CheckExternalTools -AvailableToolsForTest @()` and assert that output contains `SKIP: kubectl` and `SKIP: helm`.

- [ ] **Step 2: Run repository-policy tests and verify the expected failure**

Run:

```powershell
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1
```

Expected: FAIL because `repository-policy.ps1` does not exist.

- [ ] **Step 3: Write archive-safety fixture tests**

The test must validate these entry lists through a test parameter accepted only by the validator test harness:

```powershell
$safe = @('k3s/longhorn/values.yaml', 'k3s/kubevirt/vm/vm.yaml')
$unsafe = @('../escape.yaml', '/absolute.yaml', 'C:/absolute.yaml', 'edgar/../../escape.yaml')
```

Assert that the safe list exits `0`; assert that every unsafe entry exits `1` and appears in a `FAIL:` line.

- [ ] **Step 4: Run archive-safety tests and verify the expected failure**

Run:

```powershell
pwsh -NoProfile -File scripts/validate/test-archive-safety.ps1
```

Expected: FAIL because `archive-safety.ps1` does not exist.

- [ ] **Step 5: Implement both validators**

`repository-policy.ps1` must perform these deterministic checks:

```powershell
$forbiddenNamePatterns = @(
    '\.bak([.-]|$)', '(^|[-_])backup([-. _]|$)',
    '(^|/)rendered\.ya?ml$', '(^|/)values-default\.ya?ml$',
    '\.log$', '(^|/)snapshot-', '\.tar\.gz$', '(^|/)\.git/'
)
```

It must inspect YAML content for non-example Secret resources containing non-empty `data:` or `stringData:`, parse local `resources:` entries from every `kustomization.yaml`, reject `tests/` and `.example.yaml` references, verify local references exist, and identify duplicate `(apiVersion, kind, namespace, name)` tuples within each cluster tree. When `-CheckExternalTools` is set, detect `kubectl` and `helm` with `Get-Command`; missing commands print `SKIP`, present commands run read-only rendering checks. The internal `-AvailableToolsForTest` parameter overrides discovery only in fixture tests.

`archive-safety.ps1` must obtain entries with `tar -tzf` and reject entries matching:

```powershell
'(^/|^[A-Za-z]:|(^|/)\.\.(/|$))'
```

Expose an internal `-EntriesForTest` parameter so tests do not need to create malicious archives.

- [ ] **Step 6: Extend `.gitignore` with generated and local-secret patterns**

Append these rules and retain the existing credential and editor rules:

```gitignore
# Local Kubernetes secrets
**/*-secret.yaml
**/values.secret.yaml
!**/*-secret.example.yaml
!**/values.secret.example.yaml

# Generated, backup, and runtime artifacts
**/*.bak
**/*.bak-*
**/*.bak.*
**/*-backup*.yaml
**/backup-*/
**/rendered.yaml
**/values-default.yaml
**/*.log
**/snapshot-*
**/*.tar.gz
```

- [ ] **Step 7: Run validator fixture tests**

Run:

```powershell
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1
pwsh -NoProfile -File scripts/validate/test-archive-safety.ps1
```

Expected: both scripts print their pass summary and exit `0`.

- [ ] **Step 8: Validate both source archives before any extraction**

Run:

```powershell
pwsh -NoProfile -File scripts/validate/archive-safety.ps1 -ArchivePath 'D:/Download/Querk/k3s.tar.gz'
pwsh -NoProfile -File scripts/validate/archive-safety.ps1 -ArchivePath 'D:/Download/Querk/edgar.tar.gz'
```

Expected: `PASS:` for both archives and exit `0`.

- [ ] **Step 9: Commit the policy foundation**

```bash
git add .gitignore scripts/validate/repository-policy.ps1 scripts/validate/archive-safety.ps1 scripts/validate/test-repository-policy.ps1 scripts/validate/test-archive-safety.ps1 scripts/validate/.gitkeep
git commit -m "test: add repository configuration policy checks"
```

### Task 2: Reorganize office networking, ingress, and certificates

**Files:**
- Preserve: `clusters/k3s-office/infrastructure/networking/coredns/README.md`
- Preserve: `clusters/k3s-office/infrastructure/networking/metallb/{README.md,values.yaml,ip-address-pool.yaml,l2-advertisement.yaml,kustomization.yaml}`
- Create: `clusters/k3s-office/infrastructure/networking/multus/README.md`
- Create: `clusters/k3s-office/infrastructure/ingress/traefik/{README.md,manifests/kustomization.yaml}`
- Move: `clusters/k3s-office/infrastructure/ingress/*.yaml` to `clusters/k3s-office/infrastructure/ingress/traefik/manifests/`
- Create: `clusters/k3s-office/infrastructure/certificates/cert-manager/{README.md,manifests/kustomization.yaml}`
- Move: `clusters/k3s-office/infrastructure/letsencrypt/*.yaml` to `clusters/k3s-office/infrastructure/certificates/cert-manager/manifests/`
- Import: `k3s/nfs/cert-manager/alidns/{clusterissuer-prod.yaml,clusterissuer-staging.yaml,wildcard-prod.yaml,wildcard-staging.yaml}` into `clusters/k3s-office/infrastructure/certificates/cert-manager/manifests/alidns/`
- Import: `k3s/nfs/traefik/tls/tlsstore-default.yaml` to `clusters/k3s-office/infrastructure/ingress/traefik/manifests/kube-system-tlsstore-default.yaml`
- Move to tests: `k3s/nfs/traefik/test/test-ingress.yaml` to `clusters/k3s-office/infrastructure/ingress/traefik/tests/test-ingress.yaml`
- Delete: `clusters/k3s-office/infrastructure/ingress/.gitkeep`
- Delete: `clusters/k3s-office/infrastructure/traefik/traefik-helmchartconfig-backup.yaml`
- Test: `scripts/validate/test-metallb-config.ps1`
- Test: `scripts/validate/test-repository-policy.ps1`

**Interfaces:**
- Consumes: repository rules from Task 1.
- Produces: stable office networking, ingress, and certificate paths referenced by cluster documentation and later observability routes.

- [ ] **Step 1: Add failing path assertions**

Extend `test-repository-policy.ps1` with assertions that the new certificate and Traefik entry files exist, old `infrastructure/letsencrypt` and `infrastructure/traefik` paths do not exist, and Traefik production Kustomize excludes `tests/test-ingress.yaml`.

- [ ] **Step 2: Run the affected tests**

```powershell
pwsh -NoProfile -File scripts/validate/test-metallb-config.ps1
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: MetalLB passes; repository policy fails on old paths and tracked backup files.

- [ ] **Step 3: Extract only approved archive members into a unique temporary directory**

Use `archive-safety.ps1` first, then extract the exact members listed in this task. Do not extract archive scripts or directories wholesale. Copy YAML as data only.

- [ ] **Step 4: Move existing files and create production entries**

The Traefik manifest entry must list the eight existing ingress and middleware files. The cert-manager entry must list the four repository-baseline files plus an `alidns/` child entry. Neither entry may reference `tests/`.

- [ ] **Step 5: Write component README files**

Record purpose, prerequisites, the exact version found in the current file or archive, upstream source, exact Helm or kubectl render commands, Secret references, verification, rollback, and the fact that test manifests are opt-in. If the source contains no version, state `版本未记录，部署前必须核对上游版本` instead of inventing one.

- [ ] **Step 6: Run networking and policy checks**

```powershell
pwsh -NoProfile -File scripts/validate/test-metallb-config.ps1
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: MetalLB passes; remaining repository-policy failures belong only to later tasks and are copied into the migration checklist.

- [ ] **Step 7: Commit office network boundaries**

```bash
git add clusters/k3s-office/infrastructure/networking clusters/k3s-office/infrastructure/ingress clusters/k3s-office/infrastructure/certificates clusters/k3s-office/infrastructure/letsencrypt clusters/k3s-office/infrastructure/traefik scripts/validate/test-repository-policy.ps1
git commit -m "refactor(office): organize networking ingress and certificates"
```

### Task 3: Reorganize office storage, data services, and registry

**Files:**
- Preserve: `clusters/k3s-office/infrastructure/storage/longhorn/**`
- Move: `clusters/k3s-office/infrastructure/storage/juicefs-csi-values.yaml` to `clusters/k3s-office/infrastructure/storage/juicefs/values.yaml`
- Move: `clusters/k3s-office/infrastructure/storage/{juicefs-sc.yaml,office-files-pvc.yaml,office-pvcs.yaml}` to `clusters/k3s-office/infrastructure/storage/juicefs/manifests/`
- Replace: `clusters/k3s-office/infrastructure/storage/juicefs-secret.yaml` with `clusters/k3s-office/infrastructure/storage/juicefs/secrets/juicefs-secret.example.yaml`
- Move: `clusters/k3s-office/infrastructure/storage/juicefs-test.yaml` to `clusters/k3s-office/infrastructure/storage/juicefs/tests/`
- Move: `clusters/k3s-office/infrastructure/storage/{office-nfs-server.yaml,office-nfs-two-servers.yaml}` to `clusters/k3s-office/infrastructure/storage/nfs-server/manifests/`
- Move: `clusters/k3s-office/infrastructure/storage/office-pvc-test-pod.yaml` to `clusters/k3s-office/infrastructure/storage/nfs-server/tests/`
- Import: `k3s/nfs/nfs-server/{namespace.yaml,pvc.yaml,deployment.yaml,service.yaml}` to `clusters/k3s-office/infrastructure/storage/nfs-server/manifests/archive-nfs-server/`; these resources use Namespace `nfs-server` and do not collide with the existing `office-storage` resources.
- Move: `clusters/k3s-office/infrastructure/storage/{cnpg-juicefs-postgres.yaml,cnpg-scheduled-backup.yaml,cnpg-backup-now.yaml,postgres-lb.yaml}` to `clusters/k3s-office/infrastructure/data-services/cloudnative-pg/manifests/`
- Move: `clusters/k3s-office/infrastructure/storage/minio.yaml` to `clusters/k3s-office/infrastructure/data-services/minio/manifests/`
- Move: `clusters/k3s-office/infrastructure/storage/redis-juicefs.yaml` to `clusters/k3s-office/infrastructure/data-services/redis/manifests/`
- Move: `clusters/k3s-office/apps/harbor/harbor-values.yaml` to `clusters/k3s-office/infrastructure/registry/harbor/values.yaml`
- Import comparison source: `k3s/nfs/harbor/values.yaml`; do not import rendered or default values
- Delete: `clusters/k3s-office/infrastructure/storage/backup-yaml-2026-07-09/`
- Delete: `clusters/k3s-office/infrastructure/storage/.gitkeep`
- Delete: `clusters/k3s-office/infrastructure/registry/.gitkeep`
- Delete: `clusters/k3s-office/apps/.gitkeep`
- Test: `scripts/validate/test-longhorn-config.ps1`
- Test: `scripts/validate/test-repository-policy.ps1`

**Interfaces:**
- Consumes: repository rules from Task 1.
- Produces: stable storage, data-service, and registry paths used by office observability and virtual-machine resources.

- [ ] **Step 1: Add failing storage and Secret-example assertions**

Extend policy tests to require the destination directories, reject the old flat storage files, assert every committed `kind: Secret` with populated values ends in `.example.yaml`, and verify no example is referenced from a production Kustomize entry.

- [ ] **Step 2: Run tests and capture failures**

```powershell
pwsh -NoProfile -File scripts/validate/test-longhorn-config.ps1
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: Longhorn passes before and after the move because its path is preserved; policy fails until flat files and plaintext Secret are migrated.

- [ ] **Step 3: Migrate Longhorn archive input without replacing the repository baseline**

Compare `k3s/longhorn/values.yaml` with the preserved `values.yaml` and keep the repository version for every differing key. Record `k3s/longhorn/rendered.yaml`, `values-default.yaml`, and `test/{pvc-test.yaml,pod-test.yaml}` as not imported because the repository already has a reviewed smoke test.

- [ ] **Step 4: Move storage and data-service files**

Use Git-aware moves for tracked files. Add README and production Kustomize entries per destination. Tests remain opt-in and Secret examples remain outside production entries.

- [ ] **Step 5: Convert plaintext office Secret material**

Create `juicefs-secret.example.yaml` with the same API version, Kind, resource name, Namespace, type, and key names, replacing every value with `REPLACE_ME`. Remove the tracked plaintext source after verifying the example structure.

- [ ] **Step 6: Reconcile Harbor values**

Keep the current repository Harbor values as canonical and record `k3s/nfs/harbor/values.yaml` as not imported because it conflicts with the repository baseline. Move sensitive keys already present in the repository values into `values.secret.example.yaml`, replace their committed values with no value or the chart-safe default, and document `-f values.yaml -f values.secret.yaml`.

- [ ] **Step 7: Run storage and policy checks**

```powershell
pwsh -NoProfile -File scripts/validate/test-longhorn-config.ps1
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: Longhorn passes and no office storage/registry Secret or backup failure remains.

- [ ] **Step 8: Commit office storage and data boundaries**

```bash
git add clusters/k3s-office/infrastructure/storage clusters/k3s-office/infrastructure/data-services clusters/k3s-office/infrastructure/registry clusters/k3s-office/apps scripts/validate/test-repository-policy.ps1
git commit -m "refactor(office): organize storage data services and registry"
```

### Task 4: Reorganize office observability

**Files:**
- Move: `clusters/k3s-office/infrastructure/monitoring/kube-prometheus-stack-values.yaml` to `clusters/k3s-office/infrastructure/observability/prometheus-stack/values.yaml`
- Move: `clusters/k3s-office/infrastructure/monitoring/k3s-monitoring-fix.yaml` to `clusters/k3s-office/infrastructure/observability/prometheus-stack/manifests/`
- Move: `clusters/k3s-office/infrastructure/monitoring/blackbox-values.yaml` to `clusters/k3s-office/infrastructure/observability/exporters/blackbox/values.yaml`
- Move: `clusters/k3s-office/infrastructure/monitoring/snmp-exporter/{values.yaml,bridge-fdb-generator/generator.yml}` to `clusters/k3s-office/infrastructure/observability/exporters/snmp/`
- Move: `clusters/k3s-office/infrastructure/monitoring/juicefs-redis-exporter.yaml` to `clusters/k3s-office/infrastructure/observability/exporters/juicefs-redis/manifests/`
- Move: `clusters/k3s-office/infrastructure/monitoring/probes/*.yaml` to `clusters/k3s-office/infrastructure/observability/probes/`
- Move: `clusters/k3s-office/infrastructure/monitoring/rules/*.yaml` to `clusters/k3s-office/infrastructure/observability/rules/`
- Move: `clusters/k3s-office/infrastructure/monitoring/rules/tests/alertmanager-mattermost-test.yaml` to `clusters/k3s-office/infrastructure/observability/rules/tests/`
- Move: non-backup `clusters/k3s-office/infrastructure/monitoring/dashboards/*.yaml` to `clusters/k3s-office/infrastructure/observability/dashboards/`
- Move: `cert-manager-monitoring-values.yaml` to `clusters/k3s-office/infrastructure/observability/integrations/cert-manager/values.yaml`
- Move: `harbor-monitoring-values.yaml` to `clusters/k3s-office/infrastructure/observability/integrations/harbor/values.yaml`
- Move: `juicefs-csi-podmonitor.yaml` and `juicefs-mount-podmonitor.yaml` to `clusters/k3s-office/infrastructure/observability/integrations/juicefs/manifests/`
- Move: `metallb-{metrics-auth-rbac,monitoring-sa,podmonitor,prometheus-rbac,prometheus-token}.yaml` to `clusters/k3s-office/infrastructure/observability/integrations/metallb/manifests/`
- Move: `minio-servicemonitor.yaml` to `clusters/k3s-office/infrastructure/observability/integrations/minio/manifests/`
- Move: `clusters/k3s-office/infrastructure/monitoring/metallb-ipaddresspool.yaml` to `clusters/k3s-office/infrastructure/networking/metallb/manifests/seaweedfs-manual-pool.yaml`; its `seaweedfs-manual-pool` identity is distinct from `public-ip`
- Delete: `clusters/k3s-office/infrastructure/monitoring/backup-debug/`
- Delete: every `.bak*`, `*-backup*.yaml`, `rendered.yaml`, and `values-default.yaml` under monitoring
- Delete: `clusters/k3s-office/infrastructure/observability/.gitkeep`
- Test: `scripts/validate/test-repository-policy.ps1`

**Interfaces:**
- Consumes: Task 1 policy and Task 2/3 component paths.
- Produces: an observability tree grouped by stack, exporters, probes, rules, dashboards, and component integrations.

- [ ] **Step 1: Add failing observability assertions**

Require the six destination categories, reject `infrastructure/monitoring`, and assert the rule test file is absent from production entries.

- [ ] **Step 2: Run repository policy and confirm monitoring failures**

```powershell
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: FAIL listing backup, rendered, default-values, and old monitoring paths.

- [ ] **Step 3: Delete generated and historical artifacts first**

Remove exactly the backup and generated paths listed by `git ls-files clusters/k3s-office/infrastructure/monitoring` that match Task 1 patterns. Do not delete the canonical file with the same base name.

- [ ] **Step 4: Move canonical observability sources**

Use the mapping in this task. Create a focused README and Kustomize entry only where the files are directly applyable; Helm values directories document their `helm template` and `helm upgrade --install` commands instead.

- [ ] **Step 5: Validate test isolation and resource uniqueness**

```powershell
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: no observability backup, generated-file, test-reference, missing-reference, or duplicate-identity failures.

- [ ] **Step 6: Commit office observability**

```bash
git add clusters/k3s-office/infrastructure/monitoring clusters/k3s-office/infrastructure/observability clusters/k3s-office/infrastructure/networking/metallb scripts/validate/test-repository-policy.ps1
git commit -m "refactor(office): organize observability configuration"
```

### Task 5: Import office virtualization configuration

**Files:**
- Create: `clusters/k3s-office/infrastructure/virtualization/kubevirt/README.md`
- Import: `k3s/kubevirt/cdi/cdi-cr.yaml` to `clusters/k3s-office/infrastructure/virtualization/kubevirt/cdi/manifests/cdi.yaml`
- Do not import: `k3s/kubevirt/cdi/cdi-operator.yaml`; document pinned upstream installation instead
- Import: `k3s/kubevirt/multus/{nad-test.yaml,vm-networks.yaml}` to `clusters/k3s-office/infrastructure/virtualization/kubevirt/networking/`
- Import: `k3s/kubevirt/multus/{multus-crd.yaml,multus.yaml}` to `clusters/k3s-office/infrastructure/networking/multus/manifests/`
- Import tests: `k3s/kubevirt/multus/{multus-test-pod.yaml,vlan33-test-pod.yaml}` to `clusters/k3s-office/infrastructure/networking/multus/tests/`
- Import: `k3s/kubevirt/storage/{longhorn-kubevirt-sc.yaml,longhorn-kubevirt-storageprofile.yaml}` to `clusters/k3s-office/infrastructure/virtualization/kubevirt/storage/manifests/`
- Import test: `k3s/kubevirt/storage/test-kubevirt-pvc.yaml` to `clusters/k3s-office/infrastructure/virtualization/kubevirt/storage/tests/`
- Import: `k3s/kubevirt/vm/opensense/{opnsense-install.yaml,opnsense-installer-dv.yaml,opnsense-root-dv.yaml}` to `clusters/k3s-office/apps/virtual-machines/opnsense/`
- Import: `k3s/kubevirt/vm/ubuntu-2404/{ubuntu-2404-golden-dv.yaml,ubuntu-2404-stability01-dv.yaml,ubuntu-2404-stability01.yaml,ubuntu-2404-vpn-server-dv.yaml,ubuntu-2404-vpn-server.yaml}` to `clusters/k3s-office/apps/virtual-machines/ubuntu-2404/`
- Import tests: `k3s/kubevirt/vm/ubuntu-2404/migration.yaml` and `k3s/kubevirt/stability/{baseline.sh,collect.sh}` into component-local `tests/`
- Do not import: generic `datavolume.yaml`, `datavolume-v2.yaml`, `datavolume-v3.yaml`, `vm.yaml`, stability logs, snapshots, or nested stability archives
- Test: `scripts/validate/test-repository-policy.ps1`

**Interfaces:**
- Consumes: Multus, Longhorn, and policy checks from Tasks 1–3.
- Produces: separated platform, network, storage, test, and VM workload configuration.

- [ ] **Step 1: Add failing virtualization assertions**

Require KubeVirt README, CDI CR, network definitions, storage resources, named VM workloads, and local test isolation. Reject the vendored CDI operator and generic versioned intermediate manifests.

- [ ] **Step 2: Run tests before import**

```powershell
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: FAIL because the required virtualization destinations do not exist.

- [ ] **Step 3: Safely extract exact virtualization members**

Run `archive-safety.ps1`, extract only the members in this task, and copy them without executing `baseline.sh` or `collect.sh`.

- [ ] **Step 4: Create formal entries and documentation**

Production Kustomize entries include CDI, network, and storage resources but exclude every `tests/` path. The KubeVirt README states prerequisites and dependency order: Multus, Longhorn, CDI, KubeVirt storage integration, then VMs.

- [ ] **Step 5: Validate imported resources**

```powershell
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: no unsafe file, missing reference, duplicate identity, or test-reference failure in virtualization paths.

- [ ] **Step 6: Commit office virtualization**

```bash
git add clusters/k3s-office/infrastructure/networking/multus clusters/k3s-office/infrastructure/virtualization clusters/k3s-office/apps/virtual-machines scripts/validate/test-repository-policy.ps1
git commit -m "feat(office): organize kubevirt and virtual machines"
```

### Task 6: Reorganize lab infrastructure, applications, and policies

**Files:**
- Move: `clusters/k8s-lab/infrastructure/storage/juicefs-csi/test-{pod,pod-2,pvc}.yaml` to `clusters/k8s-lab/infrastructure/storage/juicefs-csi/tests/`
- Preserve as canonical: `clusters/k8s-lab/infrastructure/storage/juicefs-csi/values.yaml`
- Delete after comparison: `clusters/k8s-lab/infrastructure/storage/juicefs-csi/values-0.32.5.yaml`
- Replace: `clusters/k8s-lab/infrastructure/storage/juicefs-csi/juicefs-secret.yaml` with `secrets/juicefs-secret.example.yaml`
- Import: `edgar/nfs/nfs-subdir-external-provisioner/{values.yaml,nfs-test.yaml}` into `clusters/k8s-lab/infrastructure/storage/nfs-subdir-external-provisioner/`, with the test YAML under `tests/`
- Move: `clusters/k8s-lab/apps/mattermost/{mattermost.yaml,postgres-cluster.yaml}` to `clusters/k8s-lab/apps/mattermost/manifests/`
- Move: `clusters/k8s-lab/apps/mattermost/cloudflared.yaml` to `clusters/k8s-lab/apps/mattermost/cloudflared/deployment.yaml`
- Replace: the three Mattermost Secret files with same-name `.example.yaml` files under `clusters/k8s-lab/apps/mattermost/secrets/`
- Import as comparison only: `edgar/mattermost/*.yaml` and `edgar/cloudflared/cloudflared.yaml`; current repository identities win conflicts
- Import: `edgar/jira-live-monitor-k8s/{namespace.yaml,configmap.yaml,postgres.yaml,deployment.yaml,service.yaml}` into `clusters/k8s-lab/apps/jira-live-monitor/manifests/`
- Document: CNPG generates the referenced `jira-monitor-db-app` Secret; do not create a competing example Secret
- Move: `clusters/k8s-lab/policies/namespace/team-a/` to `clusters/k8s-lab/policies/namespaces/team-a/`
- Preserve: `clusters/k8s-lab/policies/authentication/csr/**` and `clusters/k8s-lab/policies/rbac/**`
- Delete: empty `.gitkeep` files under lab directories
- Test: `scripts/validate/test-repository-policy.ps1`

**Interfaces:**
- Consumes: Task 1 Secret and Kustomize policy.
- Produces: complete lab infrastructure, app, Secret-example, and policy trees.

- [ ] **Step 1: Add failing lab layout and Secret tests**

Require plural `policies/namespaces`, component-local tests, Mattermost Secret examples, Jira manifests, and the NFS Provisioner values file. Reject the old plaintext Secret and singular namespace paths.

- [ ] **Step 2: Run tests before migration**

```powershell
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: FAIL on plaintext Secrets, old lab paths, and missing Jira/NFS destinations.

- [ ] **Step 3: Migrate JuiceFS and NFS Provisioner**

Keep `values.yaml` canonical, record chart version `0.32.5` from the versioned filename in the component README, and remove `values-0.32.5.yaml` after recording the decision in the migration inventory. Move all test resources under `tests/` and keep them out of production entries.

- [ ] **Step 4: Migrate Mattermost and convert its Secrets**

Preserve resource names, Namespace, Secret types, and key names. Replace all values with `REPLACE_ME`. Keep the current tracked manifests on archive conflicts and document the local Secret-copy workflow.

- [ ] **Step 5: Import Jira Live Monitor manifests**

Do not import the adjacent application source repository. Document that the CNPG `Cluster` resource generates `jira-monitor-db-app`, which is the only Secret reference found in the supplied Jira Kubernetes manifests.

- [ ] **Step 6: Normalize policy paths and entries**

Move `namespace/team-a` to `namespaces/team-a`, preserve CSR/RBAC resources, and create Kustomize entries that apply Namespace before namespaced LimitRange and RoleBinding resources.

- [ ] **Step 7: Run lab and global policy checks**

```powershell
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: no lab plaintext Secret, old-path, test-reference, missing-reference, or duplicate-identity failure.

- [ ] **Step 8: Commit lab organization**

```bash
git add clusters/k8s-lab scripts/validate/test-repository-policy.ps1
git commit -m "refactor(lab): organize infrastructure apps and policies"
```

### Task 7: Align reusable components and documentation

**Files:**
- Modify: `README.md`
- Modify: `clusters/k3s-office/README.md`
- Modify: `clusters/k8s-lab/README.md`
- Modify: `secrets/README.md`
- Preserve and update: `components/metallb/README.md`
- Preserve and update: `components/longhorn/README.md`
- Remove: empty `components/*/base/.gitkeep` and `components/*/overlays/.gitkeep`
- Create: `docs/deployment/configuration-migration-2026-09-20.md`
- Preserve: `docs/deployment/helm.md`
- Modify: `scripts/validate/test-metallb-config.ps1`
- Modify: `scripts/validate/test-longhorn-config.ps1`

**Interfaces:**
- Consumes: final paths from Tasks 2–6.
- Produces: the user-facing repository map, manual deployment sequence, Secret workflow, and complete source-to-destination inventory.

- [ ] **Step 1: Add failing documentation assertions**

Update component tests so they require root and cluster READMEs to name the final directories, require `secrets/README.md` to show `cp *-secret.example.yaml *-secret.yaml`, and require the migration inventory to contain rows for both archives and every deleted tracked backup category.

- [ ] **Step 2: Run documentation-sensitive tests**

```powershell
pwsh -NoProfile -File scripts/validate/test-metallb-config.ps1
pwsh -NoProfile -File scripts/validate/test-longhorn-config.ps1
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root .
```

Expected: FAIL on obsolete README structure and missing migration inventory.

- [ ] **Step 3: Rewrite root and cluster navigation**

Describe cluster-first ownership, the `infrastructure/{networking,ingress,certificates,storage,data-services,registry,virtualization,observability}` responsibilities, app and policy boundaries, and dependency-aware manual deployment order. Remove statements that require every cluster to overlay `components/`.

- [ ] **Step 4: Document the local Secret workflow**

Use exact commands such as:

```bash
cp postgres-secret.example.yaml postgres-secret.yaml
kubectl apply -f postgres-secret.yaml
helm upgrade --install harbor harbor/harbor -n harbor -f values.yaml -f values.secret.yaml
```

State that local Secret files are ignored, examples are never in production Kustomize entries, Base64 is not encryption, and previously committed credentials should be rotated.

- [ ] **Step 5: Create the migration inventory**

Use a Markdown table with columns `Source`, `Destination`, `Cluster`, `Action`, and `Reason`. Include every imported archive member, every old tracked path moved or deleted, every conflicting archive resource not imported, every plaintext Secret converted, and every generated artifact category excluded.

- [ ] **Step 6: Remove empty reusable-component placeholders**

Keep component READMEs. Remove empty `base/` and `overlays/` directories until real reusable content exists. Update MetalLB and Longhorn links to their final cluster paths.

- [ ] **Step 7: Run documentation and policy checks**

```powershell
pwsh -NoProfile -File scripts/validate/test-metallb-config.ps1
pwsh -NoProfile -File scripts/validate/test-longhorn-config.ps1
pwsh -NoProfile -File scripts/validate/test-repository-policy.ps1 -Root . -CheckExternalTools
```

Expected: all static checks pass; unavailable kubectl or Helm checks print `SKIP`.

- [ ] **Step 8: Commit documentation and component cleanup**

```bash
git add README.md clusters/k3s-office/README.md clusters/k8s-lab/README.md secrets/README.md components docs/deployment scripts/validate
git commit -m "docs: document organized cluster configuration workflow"
```

### Task 8: Full repository verification and hygiene repair

**Files:**
- Modify only files named by validation failures from Tasks 1–7
- Test: all scripts under `scripts/validate/test-*.ps1`

**Interfaces:**
- Consumes: every previous task deliverable.
- Produces: a policy-clean repository with an auditable verification report.

- [ ] **Step 1: Run every PowerShell validation test**

```powershell
Get-ChildItem scripts/validate/test-*.ps1 | Sort-Object Name | ForEach-Object {
    & pwsh -NoProfile -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Validation failed: $($_.Name)" }
}
```

Expected: every test exits `0`.

- [ ] **Step 2: Run policy validation with optional tooling checks**

```powershell
pwsh -NoProfile -File scripts/validate/repository-policy.ps1 -Root . -CheckExternalTools
```

Expected: no `FAIL:` lines; missing external commands appear only as `SKIP:`.

- [ ] **Step 3: Run Git whitespace and ignored-file checks**

```bash
git diff --check
git status --short --ignored
git ls-files | rg '(\.bak([.-]|$)|rendered\.ya?ml$|values-default\.ya?ml$|\.log$|\.tar\.gz$)'
```

Expected: `git diff --check` exits `0`; the tracked forbidden-file query returns no paths; local Secret paths appear ignored rather than tracked.

- [ ] **Step 4: Review all deletions and renames**

```bash
git status --short
git diff --stat
git diff --name-status
```

Expected: every deletion or rename has a matching row in `docs/deployment/configuration-migration-2026-09-20.md`; no unrelated file is changed.

- [ ] **Step 5: Repair only evidence-backed failures and rerun the full suite**

For each policy or code failure, edit the owning task's file and add a fixture that reproduces the issue. For a documentation-only failure, add or correct the exact link/content assertion. Repeat Steps 1–4 until every required command meets its expected result.

- [ ] **Step 6: Commit final hygiene corrections**

```bash
git add -A
git commit -m "chore: complete cluster configuration migration"
```

### Task 9: Final review and handoff

**Files:**
- Review: all files changed since commit `044403c`
- Review: `docs/deployment/configuration-migration-2026-09-20.md`

**Interfaces:**
- Consumes: the verified repository from Task 8.
- Produces: final review findings and an explicit list of dynamic checks that require a Linux management node or live cluster.

- [ ] **Step 1: Review the complete diff against the design**

```bash
git diff --stat 044403c..HEAD
git diff --name-status 044403c..HEAD
```

Check every spec section against the changed-path list and migration inventory.

- [ ] **Step 2: Confirm the final worktree state**

```bash
git status --short
git log --oneline --decorate -10
```

Expected: no unintended untracked archive extraction, plaintext Secret, generated file, or temporary file remains.

- [ ] **Step 3: Report unexecuted live-environment checks**

The handoff must separately list any skipped `helm template`, `kubectl kustomize`, client dry-run, node preflight, or live-cluster verification. It must not claim those checks passed.

- [ ] **Step 4: Present the result for user review**

Summarize final paths, deleted artifact classes, Secret examples, validation evidence, skipped dynamic checks, commits, and whether changes have been pushed. Do not push unless the user explicitly requests it.
