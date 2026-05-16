param(
  [switch]$SystemCheckOnly
)
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$InstallRoot = Join-Path $Root "comfyuifeddafront"
$ComfyDir = Join-Path $InstallRoot "ComfyUI"
$NodesDir = Join-Path $ComfyDir "custom_nodes"
$NodesConfigPath = Join-Path $Root "config\base_nodes.json"
$EmbedDir = Join-Path $InstallRoot "python_embeded"
$EmbedPy = Join-Path $EmbedDir "python.exe"
$EmbedPip = Join-Path $EmbedDir "Scripts\pip.exe"

function Step([string]$msg, [string]$color = "White") {
  $ts = Get-Date -Format "HH:mm:ss"
  Write-Host "[$ts] $msg" -ForegroundColor $color
}

function Fail([string]$msg) {
  throw $msg
}

function Cmd([string]$name) {
  Get-Command $name -ErrorAction SilentlyContinue
}

function Resolve-NpmCmd {
  $candidate = Cmd "npm"
  if ($candidate) { return $candidate.Source }
  $candidate = Cmd "npm.cmd"
  if ($candidate) { return $candidate.Source }
  $default = "C:\Program Files\nodejs\npm.cmd"
  if (Test-Path $default) { return $default }
  return $null
}

function Get-GpuProfile {
  $profile = [ordered]@{
    Name = "Unknown"
    Driver = "Unknown"
    VramMB = 0
    Series = "unknown"
  }
  $smi = Cmd "nvidia-smi"
  if (-not $smi) { return [pscustomobject]$profile }
  try {
    $line = & nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if ($line) {
      $p = $line -split ","
      if ($p.Count -ge 3) {
        $profile.Name = $p[0].Trim()
        $profile.Driver = $p[1].Trim()
        $profile.VramMB = [int]($p[2].Trim())
      }
    }
  } catch {}
  if ($profile.Name -match "RTX 60\d\d") { $profile.Series = "60" }
  elseif ($profile.Name -match "RTX 50\d\d") { $profile.Series = "50" }
  elseif ($profile.Name -match "RTX 40\d\d") { $profile.Series = "40" }
  elseif ($profile.Name -match "RTX 30\d\d") { $profile.Series = "30" }
  elseif ($profile.Name -match "RTX 20\d\d|GTX 16\d\d|GTX 10\d\d") { $profile.Series = "20" }
  return [pscustomobject]$profile
}

function Show-SystemCheck {
  Step "SYSTEM CHECK" Cyan
  $gitV = if (Cmd "git") { (& git --version 2>&1) } else { "NOT FOUND" }
  $nodeV = if (Cmd "node") { (& node --version 2>&1) } else { "NOT FOUND" }
  $npmCmd = Resolve-NpmCmd
  $npmV = if ($npmCmd) { (& $npmCmd --version 2>&1) } else { "NOT FOUND" }
  $gpu = Get-GpuProfile
  $ramGB = 0
  try { $ramGB = [math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1MB) } catch {}
  $drive = (Get-Item $Root).PSDrive
  $freeGB = [math]::Round($drive.Free / 1GB)
  Step "Git:     $gitV" Green
  Step "Node.js: $nodeV" Green
  Step "npm:     $npmV" Green
  Step "GPU:     $($gpu.Name) | Driver $($gpu.Driver) | VRAM $([math]::Round($gpu.VramMB/1024,1)) GB" Green
  Step "RAM:     $ramGB GB" Green
  Step "Disk:    $freeGB GB free on $($drive.Name):\" Green
}

function Ensure-EmbeddedPython {
  if (Test-Path $EmbedPy) {
    Step "Embedded Python already present." Green
    return
  }
  Step "Installing embedded Python 3.11.9..." Yellow
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  $zip = Join-Path $InstallRoot "python_embed.zip"
  & curl.exe -L -o $zip "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" --retry 3 --retry-delay 2 --progress-bar
  if ($LASTEXITCODE -ne 0) { Fail "Failed downloading embedded python." }
  New-Item -ItemType Directory -Force -Path $EmbedDir | Out-Null
  Expand-Archive -Path $zip -DestinationPath $EmbedDir -Force
  Remove-Item $zip -Force

  $pth = Join-Path $EmbedDir "python311._pth"
  if (Test-Path $pth) {
    $content = Get-Content $pth
    $content = $content -replace "#import site", "import site"
    if ($content -notcontains "../ComfyUI") { $content += "../ComfyUI" }
    Set-Content -Path $pth -Value $content
  }

  $getPip = Join-Path $InstallRoot "get-pip.py"
  & curl.exe -L -o $getPip "https://bootstrap.pypa.io/get-pip.py" --retry 3 --retry-delay 2
  if ($LASTEXITCODE -ne 0) { Fail "Failed downloading get-pip.py" }
  & $EmbedPy $getPip
  if ($LASTEXITCODE -ne 0) { Fail "Failed bootstrapping pip in embedded python." }
  Remove-Item $getPip -Force
  Step "Embedded Python ready." Green
}

function Get-TorchIndexesForSeries([string]$series) {
  $override = [string]$env:FEDDA_TORCH_INDEXES
  if (-not [string]::IsNullOrWhiteSpace($override)) {
    return $override.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  }
  if ($series -eq "60" -or $series -eq "50") {
    return @(
      "https://download.pytorch.org/whl/cu128",
      "https://download.pytorch.org/whl/cu126",
      "https://download.pytorch.org/whl/cu124",
      "https://download.pytorch.org/whl/cu121"
    )
  }
  if ($series -eq "40" -or $series -eq "30") {
    return @(
      "https://download.pytorch.org/whl/cu124",
      "https://download.pytorch.org/whl/cu121",
      "https://download.pytorch.org/whl/cu118"
    )
  }
  return @(
    "https://download.pytorch.org/whl/cu121",
    "https://download.pytorch.org/whl/cu118"
  )
}

function Install-TorchStack([string[]]$indexes, [string]$series) {
  $spec = @("torch==2.6.0", "torchvision==0.21.0", "torchaudio==2.6.0")
  foreach ($idx in $indexes) {
    Step "Trying torch stack from $idx ..." Yellow
    & $EmbedPy -m pip install --upgrade --force-reinstall @spec --index-url $idx --no-warn-script-location
    if ($LASTEXITCODE -eq 0) {
      Step "Torch stack installed from $idx." Green
      if ($series -eq "50" -or $series -eq "60") {
        Step "RTX 50/60 detected: removing xformers (prefer SDPA)." DarkGray
        & $EmbedPy -m pip uninstall -y xformers --no-warn-script-location 2>&1 | Out-Null
      } else {
        Step "Installing xformers (best effort)..." DarkGray
        & $EmbedPy -m pip install xformers==0.0.29.post3 --index-url https://download.pytorch.org/whl/cu124 --no-warn-script-location
      }
      return $idx
    }
    Step "Torch stack failed on $idx" DarkYellow
  }
  Fail "PyTorch CUDA installation failed for this system."
}

function Ensure-ComfyUi {
  if (-not (Test-Path $InstallRoot)) { New-Item -ItemType Directory -Path $InstallRoot | Out-Null }
  if (-not (Test-Path $ComfyDir)) {
    Step "Cloning ComfyUI..." Yellow
    & git clone https://github.com/comfyanonymous/ComfyUI.git $ComfyDir
    if ($LASTEXITCODE -ne 0) { Fail "Failed to clone ComfyUI." }
    Step "ComfyUI cloned." Green
  } else {
    Step "ComfyUI already present, pulling latest..." Yellow
    Push-Location $ComfyDir
    & git pull --ff-only
    if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "Failed to update ComfyUI." }
    Pop-Location
    Step "ComfyUI updated." Green
  }
}

function Ensure-BaseNodes {
  if (-not (Test-Path $NodesDir)) { New-Item -ItemType Directory -Path $NodesDir | Out-Null }
  if (-not (Test-Path $NodesConfigPath)) { Fail "Missing nodes config: $NodesConfigPath" }
  $nodes = Get-Content $NodesConfigPath | ConvertFrom-Json
  foreach ($n in $nodes) {
    $target = Join-Path $NodesDir $n.folder
    if (-not (Test-Path $target)) {
      Step "Installing node: $($n.name)" Yellow
      & git clone --depth 1 $n.repo $target
      if ($LASTEXITCODE -ne 0) { Fail "Failed to clone node: $($n.name)" }
    } else {
      Step "Updating node: $($n.name)" DarkGray
      Push-Location $target
      & git pull --ff-only
      Pop-Location
    }
  }
}

function Ensure-FrontendDeps {
  $frontendDir = Join-Path $Root "frontend"
  $npmCmd = Resolve-NpmCmd
  if (-not $npmCmd) { Fail "npm is required but not found in PATH." }
  if (Test-Path (Join-Path $frontendDir "package.json")) {
    Step "Installing frontend dependencies..." Yellow
    Push-Location $frontendDir
    & $npmCmd install
    if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "npm install failed in frontend." }
    Pop-Location
    Step "Frontend dependencies installed." Green
  }
}

Step "FEDDA v12 base install starting..." Cyan
Step "Install root: $InstallRoot" DarkGray
Show-SystemCheck

if (-not (Cmd "git")) { Fail "Git is required but not found in PATH." }
if (-not (Cmd "node")) { Fail "Node.js is required but not found in PATH." }
if (-not (Cmd "curl.exe")) { Fail "curl.exe is required but not found in PATH." }

if ($SystemCheckOnly) {
  Step "System check only complete." Green
  exit 0
}

Ensure-ComfyUi
Ensure-EmbeddedPython

Step "Installing ComfyUI Python requirements..." Yellow
$req = Join-Path $ComfyDir "requirements.txt"
if (Test-Path $req) {
  & $EmbedPy -m pip install -r $req --no-warn-script-location
  if ($LASTEXITCODE -ne 0) { Fail "Failed installing ComfyUI requirements." }
}

$gpu = Get-GpuProfile
$torchIndexes = Get-TorchIndexesForSeries $gpu.Series
Step "Torch fallback order: $($torchIndexes -join ' -> ')" DarkGray
$selectedTorchIndex = Install-TorchStack -indexes $torchIndexes -series $gpu.Series
Step "Torch source selected: $selectedTorchIndex" DarkGray

Ensure-BaseNodes
Ensure-FrontendDeps

Step "Running torch/CUDA smoke test..." Yellow
& $EmbedPy -c "import torch;print('PyTorch', torch.__version__, 'CUDA', torch.cuda.is_available())"
if ($LASTEXITCODE -ne 0) { Fail "Smoke test failed." }

Step "Base install complete." Green
Step "ComfyUI path: $ComfyDir" DarkGray
Step "Nodes path: $NodesDir" DarkGray
Step "Embedded python: $EmbedPy" DarkGray
