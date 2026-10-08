$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependencias fallidas' }
  flutter build web --release --no-web-resources-cdn
  if ($LASTEXITCODE -ne 0) { throw 'Compilación fallida' }
  python scripts/prepare_pwa.py
  if ($LASTEXITCODE -ne 0) { throw 'Preparación PWA fallida' }
} finally { Pop-Location }
