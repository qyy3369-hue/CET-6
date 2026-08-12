param(
    [string]$ModelId = "shun89/opus-mt-ja-zh",
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$project = Split-Path -Parent $PSScriptRoot
$onnxDir = Join-Path $project "Windows\Goals.Windows\Models\opus-mt-ja-zh"
$ready = @(
    "encoder_model.onnx",
    "decoder_model.onnx",
    "decoder_with_past_model.onnx",
    "source_vocab.json",
    "target_vocab.json"
)

$missing = $ready | Where-Object { -not (Test-Path (Join-Path $onnxDir $_) -PathType Leaf) }
if ($missing.Count -eq 0) {
    Write-Host "Translation model is ready: $onnxDir"
    exit 0
}

if (-not $Python) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCommand) {
        throw "Python was not found. Install Python 3.12 and the model export dependencies."
    }
    $Python = $pythonCommand.Source
}

$exportScript = Join-Path $PSScriptRoot "export_translation_model.py"
New-Item -ItemType Directory -Force -Path $onnxDir | Out-Null

Write-Host "Exporting the Japanese-to-Chinese ONNX model..."
& $Python $exportScript --model-id $ModelId --output $onnxDir
if ($LASTEXITCODE -ne 0) {
    throw "Model export failed with exit code $LASTEXITCODE."
}

$missing = $ready | Where-Object { -not (Test-Path (Join-Path $onnxDir $_) -PathType Leaf) }
if ($missing.Count -gt 0) {
    throw "Model export is missing required files: $($missing -join ', ')"
}

Write-Host "Translation model generated: $onnxDir"
