from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import onnxruntime as ort


EXPECTED_INPUT_NAME = "input_1"
EXPECTED_OUTPUT_NAME = "embedding"
EXPECTED_INPUT_SHAPE = [1, 112, 112, 3]
EXPECTED_EMBEDDING_SIZE = 512


def normalize_shape(shape: list[object]) -> list[int | str]:
    normalized: list[int | str] = []
    for value in shape:
        if isinstance(value, int):
            normalized.append(value)
        else:
            normalized.append(str(value))
    return normalized


def verify_model(model_path: Path) -> dict[str, object]:
    session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    inputs = session.get_inputs()
    outputs = session.get_outputs()

    if len(inputs) != 1:
        raise ValueError(f"Expected 1 input, found {len(inputs)}")
    if len(outputs) != 1:
        raise ValueError(f"Expected 1 output, found {len(outputs)}")

    input_info = inputs[0]
    output_info = outputs[0]
    input_shape = normalize_shape(input_info.shape)
    output_shape = normalize_shape(output_info.shape)

    if input_info.name != EXPECTED_INPUT_NAME:
        raise ValueError(f"Expected input name {EXPECTED_INPUT_NAME}, found {input_info.name}")
    if output_info.name != EXPECTED_OUTPUT_NAME:
        raise ValueError(f"Expected output name {EXPECTED_OUTPUT_NAME}, found {output_info.name}")
    if input_shape[1:] != EXPECTED_INPUT_SHAPE[1:]:
        raise ValueError(f"Expected spatial input shape {EXPECTED_INPUT_SHAPE}, found {input_shape}")
    if output_shape[-1] != EXPECTED_EMBEDDING_SIZE:
        raise ValueError(f"Expected embedding width {EXPECTED_EMBEDDING_SIZE}, found {output_shape}")

    return {
        "input_name": input_info.name,
        "input_shape": input_shape,
        "input_type": input_info.type,
        "output_name": output_info.name,
        "output_shape": output_shape,
        "output_type": output_info.type,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify and package the EyePal ONNX face embedding model.")
    parser.add_argument("--model", required=True, type=Path, help="Path to arcface_fresh.onnx")
    parser.add_argument("--output-dir", required=True, type=Path, help="Directory where the validated model bundle will be written.")
    args = parser.parse_args()

    if not args.model.is_file():
        raise FileNotFoundError(f"Model not found: {args.model}")

    summary = verify_model(args.model)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    output_model = args.output_dir / "arcface_fresh.onnx"
    shutil.copy2(args.model, output_model)

    summary_path = args.output_dir / "arcface_contract.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"Packaged ONNX model at {output_model}")
    print(f"Wrote contract summary to {summary_path}")


if __name__ == "__main__":
    main()
