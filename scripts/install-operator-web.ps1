[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$CommandGlowsSitePath
)
$ErrorActionPreference = 'Stop'
$engineRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $engineRoot 'app\build\web'
if (-not (Test-Path -LiteralPath (Join-Path $source 'index.html'))) {
  throw 'Build app with flutter build web --release --base-href /email-engine/ first.'
}
$site = (Resolve-Path -LiteralPath $CommandGlowsSitePath).Path
if (-not (Test-Path -LiteralPath (Join-Path $site 'src\pages\api\admin\email\[...path].ts'))) {
  throw 'Target must be the CommandGlows site containing the campaign admin API.'
}
$publicRoot = (Resolve-Path -LiteralPath (Join-Path $site 'public')).Path
$destination = [IO.Path]::GetFullPath((Join-Path $publicRoot 'email-engine'))
if ($destination -ne ($publicRoot.TrimEnd('\') + '\email-engine')) {
  throw 'Unexpected output target.'
}
if (Test-Path -LiteralPath $destination) {
  $targetItem = Get-Item -LiteralPath $destination -Force
  if ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Refusing a linked output directory.'
  }
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $destination -Recurse -Force
Write-Output 'Operator web artifact installed locally. This does not deploy or activate sending.'
