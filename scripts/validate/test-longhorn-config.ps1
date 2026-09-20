$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$longhornRoot = Join-Path $repositoryRoot 'clusters/k3s-office/infrastructure/storage/longhorn'

$requiredFiles = @(
    'README.md',
    'values.yaml',
    'smoke-test/namespace.yaml',
    'smoke-test/pvc.yaml',
    'smoke-test/pod.yaml',
    'smoke-test/kustomization.yaml'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $longhornRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required Longhorn file: $path"
    }
}

$values = Get-Content -Raw -LiteralPath (Join-Path $longhornRoot 'values.yaml')
foreach ($expected in @(
    'defaultClassReplicaCount: 2',
    'defaultDataPath: /var/lib/longhorn',
    'replicaSoftAntiAffinity: false',
    'replicaAutoBalance: least-effort',
    'storageOverProvisioningPercentage: 100',
    'storageMinimalAvailablePercentage: 10',
    'defaultReplicaCount: 2',
    'allowVolumeCreationWithDegradedAvailability: false',
    'v1DataEngine: true',
    'v2DataEngine: false'
)) {
    if (-not $values.Contains($expected)) { throw "Longhorn values.yaml is missing: $expected" }
}

$readme = Get-Content -Raw -LiteralPath (Join-Path $longhornRoot 'README.md')
foreach ($expected in @('--version 1.12.1', 'helm upgrade --install longhorn', 'longhorn-node-preflight.sh')) {
    if (-not $readme.Contains($expected)) { throw "Longhorn README is missing: $expected" }
}

$pvc = Get-Content -Raw -LiteralPath (Join-Path $longhornRoot 'smoke-test/pvc.yaml')
foreach ($expected in @('namespace: longhorn-smoke-test', 'storageClassName: longhorn', 'storage: 10Gi')) {
    if (-not $pvc.Contains($expected)) { throw "Longhorn smoke-test PVC is missing: $expected" }
}

$pod = Get-Content -Raw -LiteralPath (Join-Path $longhornRoot 'smoke-test/pod.yaml')
foreach ($expected in @('namespace: longhorn-smoke-test', 'image: busybox:1.37.0', 'claimName: longhorn-test')) {
    if (-not $pod.Contains($expected)) { throw "Longhorn smoke-test Pod is missing: $expected" }
}

$componentReadme = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'components/longhorn/README.md')
if (-not $componentReadme.Contains('https://charts.longhorn.io')) {
    throw 'Reusable Longhorn README must record the official Helm repository.'
}

$preflight = Join-Path $repositoryRoot 'scripts/validate/longhorn-node-preflight.sh'
if (-not (Test-Path -LiteralPath $preflight -PathType Leaf)) {
    throw "Missing Longhorn node preflight script: $preflight"
}

$coreDnsReadme = Join-Path $repositoryRoot 'clusters/k3s-office/infrastructure/networking/coredns/README.md'
if (-not (Test-Path -LiteralPath $coreDnsReadme -PathType Leaf)) {
    throw "Missing CoreDNS runbook: $coreDnsReadme"
}
$coreDnsContent = Get-Content -Raw -LiteralPath $coreDnsReadme
if (-not $coreDnsContent.Contains('--replicas=2')) {
    throw 'CoreDNS runbook must record the two-replica setting.'
}

Write-Output 'Longhorn and CoreDNS configuration validation passed.'
