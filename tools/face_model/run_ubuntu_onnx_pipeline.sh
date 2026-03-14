#!/usr/bin/env bash
set -euo pipefail

MODEL_PATH="${1:-tools/face_model/models/arcface_fresh.onnx}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv-ubuntu"
OUTPUT_DIR="$ROOT_DIR/tools/face_model/dist"

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip
python -m pip install -r "$ROOT_DIR/tools/face_model/requirements.txt"
python "$ROOT_DIR/tools/face_model/package_onnx_model.py" \
  --model "$ROOT_DIR/$MODEL_PATH" \
  --output-dir "$OUTPUT_DIR"

echo "Ubuntu ONNX pipeline complete. Output: $OUTPUT_DIR/arcface_fresh.onnx"
