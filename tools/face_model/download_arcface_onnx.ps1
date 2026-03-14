param(
    [string]$OutDir = "tools\face_model\models"
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$modelUrl = "https://huggingface.co/garavv/arcface-onnx/resolve/main/arc.onnx?download=true"
$outFile = Join-Path $OutDir "arcface.onnx"
$tempFile = Join-Path $OutDir "arcface.download.onnx"

if (Test-Path $tempFile) {
    Remove-Item $tempFile -Force
}

Write-Host "Downloading ArcFace embedding model to a temporary file..."
Invoke-WebRequest -Uri $modelUrl -OutFile $tempFile

if (Test-Path $outFile) {
    Remove-Item $outFile -Force
}

Move-Item $tempFile $outFile
Write-Host "Saved model to $outFile"
