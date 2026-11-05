$ErrorActionPreference = 'Stop'
$target = Join-Path $PWD 'runtime'
New-Item -ItemType Directory -Force $target | Out-Null
$version = '3.13.9'
$zip = Join-Path $env:TEMP "python-$version-embed-amd64.zip"
Invoke-WebRequest "https://www.python.org/ftp/python/$version/python-$version-embed-amd64.zip" -OutFile $zip
Expand-Archive -Force $zip $target
python -m pip install --disable-pip-version-check --only-binary=:all: --target "$target/Lib/site-packages" -r ../../voice_engine/requirements.lock.txt
if ($LASTEXITCODE -ne 0) { throw 'Python dependencies failed' }
Add-Content "$target/python313._pth" "`nLib/site-packages`nimport site"
Copy-Item speech/worker.py,speech/models.py,../../voice_engine/engine.py $target
& "$target/python.exe" -c "import numpy, scipy, soundfile, onnxruntime, sherpa_onnx"
if ($LASTEXITCODE -ne 0) { throw 'Embedded runtime failed to import' }
