$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$metalLbRoot = Join-Path $repositoryRoot 'clusters/k3s-office/infrastructure/networking/metallb'

$requiredFiles = @(
    'README.md',
    'values.yaml',
    'ip-address-pool.yaml',
    'l2-advertisement.yaml',
    'kustomization.yaml'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $metalLbRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required MetalLB file: $path"
    }
}

$values = Get-Content -Raw -LiteralPath (Join-Path $metalLbRoot 'values.yaml')
if ($values -notmatch '(?ms)^frrk8s:\s*\r?\n\s+enabled:\s*false\s*$') {
    throw 'values.yaml must disable frrk8s for the selected native mode.'
}
if ($values -notmatch '(?ms)^speaker:\s*\r?\n\s+frr:\s*\r?\n\s+enabled:\s*false\s*$') {
    throw 'values.yaml must explicitly disable speaker.frr for native mode.'
}

$pool = Get-Content -Raw -LiteralPath (Join-Path $metalLbRoot 'ip-address-pool.yaml')
foreach ($expected in @('kind: IPAddressPool', 'name: public-ip', 'namespace: metallb-system', '101.36.148.184/32')) {
    if (-not $pool.Contains($expected)) { throw "IPAddressPool is missing: $expected" }
}

$advertisement = Get-Content -Raw -LiteralPath (Join-Path $metalLbRoot 'l2-advertisement.yaml')
foreach ($expected in @('kind: L2Advertisement', 'name: public-l2', 'namespace: metallb-system', '- public-ip', '- vlan33')) {
    if (-not $advertisement.Contains($expected)) { throw "L2Advertisement is missing: $expected" }
}

$kustomization = Get-Content -Raw -LiteralPath (Join-Path $metalLbRoot 'kustomization.yaml')
foreach ($expected in @('- ip-address-pool.yaml', '- l2-advertisement.yaml')) {
    if (-not $kustomization.Contains($expected)) { throw "kustomization.yaml is missing: $expected" }
}

$clusterReadme = Get-Content -Raw -LiteralPath (Join-Path $metalLbRoot 'README.md')
foreach ($expected in @('--version 0.16.1', 'metallb.io/address-pool=public-ip', 'metallb.io/loadBalancerIPs=101.36.148.184')) {
    if (-not $clusterReadme.Contains($expected)) { throw "Cluster MetalLB README is missing: $expected" }
}

$componentReadme = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'components/metallb/README.md')
if (-not $componentReadme.Contains('https://metallb.github.io/metallb')) {
    throw 'Reusable MetalLB README must record the official Helm repository.'
}

$helmGuide = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot 'docs/deployment/helm.md')
foreach ($expected in @('DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6', 'https://packages.buildkite.com/helm-linux/helm-debian/any/')) {
    if (-not $helmGuide.Contains($expected)) { throw "Helm installation guide is missing: $expected" }
}

Write-Output 'MetalLB configuration validation passed.'
