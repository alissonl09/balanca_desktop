param(
  [string]$SevenZipPath,
  [string]$InstallerPath
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeRoot = Join-Path $repoRoot 'runtime\windows\tesseract'
$downloadRoot = Join-Path $repoRoot 'build\ocr-download'
$expectedHash = 'BEE9E3434BD94FD65387D9BE28CD467A41F61B1275383B55B0F59A1331270AE4'
# Source and digest: official tesseract-ocr/tesseract release 5.5.3.
$url = 'https://github.com/tesseract-ocr/tesseract/releases/download/5.5.3/tesseract-ocr-w64-setup-5.5.3.20260724.exe'
if (!$SevenZipPath) {
  $sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
  if ($sevenZip) { $SevenZipPath = $sevenZip.Source }
  elseif (Test-Path -LiteralPath 'C:\Program Files\7-Zip\7z.exe') {
    $SevenZipPath = 'C:\Program Files\7-Zip\7z.exe'
  }
}
if (!$SevenZipPath -or !(Test-Path -LiteralPath $SevenZipPath)) {
  throw 'Informe -SevenZipPath com o caminho do 7z.exe (somente na máquina de build).'
}
New-Item -ItemType Directory -Force -Path $downloadRoot, $runtimeRoot | Out-Null
if (!$InstallerPath) {
  $InstallerPath = Join-Path $downloadRoot 'tesseract-setup.exe'
  if (!(Test-Path -LiteralPath $InstallerPath)) {
    Invoke-WebRequest -Uri $url -OutFile $InstallerPath
  }
}
if ((Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash -ne $expectedHash) {
  throw 'Hash do pacote Tesseract diferente da publicação oficial. Extração cancelada.'
}
# Extract only. Never run the installer or change PATH/registry/system folders.
& $SevenZipPath x '-y' "-o$runtimeRoot" $InstallerPath 'tesseract.exe' '*.dll' 'tessdata\eng.traineddata' 'tessdata\configs\tsv' 'doc\*' '-xr!$PLUGINSDIR'
if ($LASTEXITCODE -ne 0) { throw 'Falha ao extrair o runtime OCR.' }
$modelPath = Join-Path $runtimeRoot 'tessdata\eng.traineddata'
if (!(Test-Path -LiteralPath $modelPath)) {
  New-Item -ItemType Directory -Force -Path (Split-Path $modelPath) | Out-Null
  Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/4.1.0/eng.traineddata' -OutFile $modelPath
}
if ((Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash -ne '8280AED0782FE27257A68EA10FE7EF324CA0F8D85BD2FD145D1C2B560BCB66BA') {
  throw 'Hash do modelo OCR inválido.'
}
# Specialized models are source assets, never fetched on an operator station.
$ssdSource = Join-Path $repoRoot 'assets\ocr'
$ssdManifest = Get-Content -LiteralPath (Join-Path $ssdSource 'SOURCE.json') -Raw | ConvertFrom-Json
foreach ($modelName in @('7seg.traineddata', 'ssd.traineddata', 'ssd_int.traineddata')) {
  $sourceModel = Join-Path $ssdSource "tessdata\$modelName"
  $expectedModelHash = $ssdManifest.files.$modelName.sha256
  if ((Get-FileHash -LiteralPath $sourceModel -Algorithm SHA256).Hash -ne $expectedModelHash) {
    throw "Modelo especializado ausente ou corrompido: $modelName"
  }
  Copy-Item -LiteralPath $sourceModel -Destination (Join-Path (Split-Path $modelPath) $modelName)
}
$ssdNotices = Join-Path $runtimeRoot 'licenses\tessdata_ssd'
New-Item -ItemType Directory -Force -Path $ssdNotices | Out-Null
foreach ($noticeName in @('LICENSE.tessdata_ssd', 'SOURCE.json', 'UPSTREAM-README.md', 'NOTICE.txt')) {
  Copy-Item -LiteralPath (Join-Path $ssdSource $noticeName) -Destination $ssdNotices
}
& (Join-Path $runtimeRoot 'tesseract.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'Engine extraída não executa nesta máquina.' }
& (Join-Path $runtimeRoot 'tesseract.exe') --tessdata-dir (Join-Path $runtimeRoot 'tessdata') --list-langs
if ($LASTEXITCODE -ne 0) { throw 'Engine não conseguiu carregar o modelo.' }
Write-Output "Runtime pronto em $runtimeRoot. Compile e distribua a pasta completa do aplicativo."
