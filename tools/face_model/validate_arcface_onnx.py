import argparse
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort


def preprocess(image_path: Path) -> np.ndarray:
    image = cv2.imread(str(image_path))
    if image is None:
        raise FileNotFoundError(f"Could not read image: {image_path}")

    image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    image = cv2.resize(image, (112, 112), interpolation=cv2.INTER_LINEAR)
    image = (image.astype(np.float32) - 127.5) / 128.0
    return image[np.newaxis, ...]


def normalize(vector: np.ndarray) -> np.ndarray:
    norm = np.linalg.norm(vector)
    if norm == 0:
        return vector
    return vector / norm


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    a = normalize(a)
    b = normalize(b)
    return float(np.dot(a, b))


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate ArcFace ONNX embeddings with two images.")
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--image-a", required=True, type=Path)
    parser.add_argument("--image-b", required=True, type=Path)
    args = parser.parse_args()

    session = ort.InferenceSession(str(args.model), providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    output_name = session.get_outputs()[0].name

    embedding_a = session.run([output_name], {input_name: preprocess(args.image_a)})[0][0]
    embedding_b = session.run([output_name], {input_name: preprocess(args.image_b)})[0][0]

    score = cosine_similarity(embedding_a, embedding_b)
    print(f"Cosine similarity: {score:.4f}")

    if score >= 0.82:
        print("Likely same person at the current EyePals threshold.")
    else:
        print("Likely different people or a weak crop at the current EyePals threshold.")


if __name__ == "__main__":
    main()
