$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$InstallRoot = Join-Path $Root "comfyuifeddafront"
$ComfyDir = Join-Path $InstallRoot "ComfyUI"
$NodesDir = Join-Path $ComfyDir "custom_nodes"
$NodesConfigPath = Join-Path $Root "config\base_nodes.json"

function Step([string]$msg, [string]$color = "White") {
  $ts = Get-Date -Format "HH:mm:ss"
  Write-Host "[$ts] $msg" -ForegroundColor $color
}

Step "FEDDA v12 base install starting..." Cyan
Step "Install root: $InstallRoot" DarkGray

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "Git is required but not found in PATH."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw "Node.js is required but not found in PATH."
}
$npmCmd = $null
$npmLookup = Get-Command npm -ErrorAction SilentlyContinue
if ($npmLookup) { $npmCmd = $npmLookup.Source }
if (-not $npmCmd) {
  $npmLookup = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if ($npmLookup) { $npmCmd = $npmLookup.Source }
}
if (-not $npmCmd) {
  $npmDefault = "C:\Program Files\nodejs\npm.cmd"
  if (Test-Path $npmDefault) { $npmCmd = $npmDefault }
}
if (-not $npmCmd) {
  throw "npm is required but not found in PATH."
}

if (-not (Test-Path $InstallRoot)) {
  New-Item -ItemType Directory -Path $InstallRoot | Out-Null
}

if (-not (Test-Path $ComfyDir)) {
  Step "Cloning ComfyUI..." Yellow
  & git clone https://github.com/comfyanonymous/ComfyUI.git $ComfyDir
  if ($LASTEXITCODE -ne 0) { throw "Failed to clone ComfyUI." }
  Step "ComfyUI cloned." Green
} else {
  Step "ComfyUI already present, pulling latest..." Yellow
  Push-Location $ComfyDir
  & git pull --ff-only
  if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "Failed to update ComfyUI."
  }
  Pop-Location
  Step "ComfyUI updated." Green
}

if (-not (Test-Path $NodesDir)) {
  New-Item -ItemType Directory -Path $NodesDir | Out-Null
}

if (-not (Test-Path $NodesConfigPath)) {
  throw "Missing nodes config: $NodesConfigPath"
}

$nodes = Get-Content $NodesConfigPath | ConvertFrom-Json

foreach ($n in $nodes) {
  $target = Join-Path $NodesDir $n.folder
  if (-not (Test-Path $target)) {
    Step "Installing node: $($n.name)" Yellow
    & git clone --depth 1 $n.repo $target
    if ($LASTEXITCODE -ne 0) { throw "Failed to clone node: $($n.name)" }
  } else {
    Step "Updating node: $($n.name)" DarkGray
    Push-Location $target
    & git pull --ff-only
    Pop-Location
  }
}

$FrontendDir = Join-Path $Root "frontend"
if (Test-Path (Join-Path $FrontendDir "package.json")) {
  Step "Installing frontend dependencies..." Yellow
  Push-Location $FrontendDir
  & $npmCmd install
  if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "npm install failed in frontend."
  }
  Pop-Location
  Step "Frontend dependencies installed." Green
}

Step "Base install complete." Green
Step "ComfyUI path: $ComfyDir" DarkGray
Step "Nodes path: $NodesDir" DarkGray
