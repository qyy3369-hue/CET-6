"""Export the bundled Japanese-to-Chinese model used by Goals for Windows."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

import sentencepiece as spm
from huggingface_hub import hf_hub_download
from onnxruntime.quantization import QuantType, quantize_dynamic
from optimum.onnxruntime import ORTModelForSeq2SeqLM


REQUIRED_ONNX_FILES = (
    "encoder_model.onnx",
    "decoder_model.onnx",
    "decoder_with_past_model.onnx",
)


def dump_vocab(model_path: Path, output_path: Path) -> None:
    processor = spm.SentencePieceProcessor(model_file=str(model_path))
    add_dummy_prefix = True
    escape_whitespaces = True
    remove_extra_whitespaces = False
    try:
        trainer_spec = processor.get_proto().trainer_spec
        add_dummy_prefix = bool(trainer_spec.add_dummy_prefix)
        escape_whitespaces = bool(trainer_spec.escape_whitespaces)
        remove_extra_whitespaces = bool(trainer_spec.remove_extra_whitespaces)
    except (AttributeError, RuntimeError):
        pass
    payload = {
        "pieces": [
            [processor.id_to_piece(index), processor.get_score(index)]
            for index in range(processor.get_piece_size())
        ],
        "pad_id": processor.pad_id(),
        "bos_id": processor.bos_id(),
        "eos_id": processor.eos_id(),
        "unk_id": processor.unk_id(),
        "add_dummy_prefix": add_dummy_prefix,
        "escape_whitespaces": escape_whitespaces,
        "remove_extra_whitespaces": remove_extra_whitespaces,
    }
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False), encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-id", default="shun89/opus-mt-ja-zh")
    parser.add_argument("--revision", default="0728b51")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
    args.output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="goals-opus-mt-") as temp_directory:
        float_output = Path(temp_directory)
        model = ORTModelForSeq2SeqLM.from_pretrained(
            args.model_id,
            revision=args.revision,
            export=True,
        )
        model.save_pretrained(float_output)
        del model

        for name in REQUIRED_ONNX_FILES:
            quantize_dynamic(
                model_input=float_output / name,
                model_output=args.output / name,
                weight_type=QuantType.QInt8,
            )

    for source_name, output_name in (
        ("source.spm", "source_vocab.json"),
        ("target.spm", "target_vocab.json"),
    ):
        source_path = Path(
            hf_hub_download(
                repo_id=args.model_id,
                filename=source_name,
                revision=args.revision,
            )
        )
        dump_vocab(source_path, args.output / output_name)

    required = [
        *(args.output / name for name in REQUIRED_ONNX_FILES),
        args.output / "source_vocab.json",
        args.output / "target_vocab.json",
    ]
    missing = [
        str(path) for path in required if not path.is_file() or path.stat().st_size == 0
    ]
    if missing:
        raise RuntimeError(f"Model export did not produce required files: {missing}")

    print(f"Translation model exported to {args.output}")


if __name__ == "__main__":
    main()
