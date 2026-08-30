#!/usr/bin/env python3
"""Check checked-out vintage clients against the canonical RUBP endpoint."""

import argparse
import json
from pathlib import Path

CLIENTS = {
    "rachel-commodore-amiga": "src/net",
    "rachel-acorn-bbc": "src",
    "rachel-coleco-colecovision": "src",
    "rachel-dragon-32": "src",
    "rachel-acorn-electron": "src",
    "rachel-nintendo-gameboy": "src",
    "rachel-nintendo-nes": "src",
    "rachel-sega-gamegear": "src",
    "rachel-sega-mastersystem": "src",
    "rachel-commodore-vic20": "src",
}
TEXT_SUFFIXES = {".asm", ".inc", ".md", ".py"}


def source_text(path: Path) -> str:
    return "\n".join(
        file.read_text(errors="replace")
        for file in path.rglob("*")
        if file.is_file() and file.suffix.lower() in TEXT_SUFFIXES
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    contract = json.loads(
        (Path(__file__).parents[1] / "specs/rubp-transport-v1.json").read_text()
    )
    port = str(contract["raw_tcp"]["default_port"])
    failures: list[str] = []
    for repo, relative_source in CLIENTS.items():
        source = args.root / repo / relative_source
        if not source.is_dir():
            failures.append(f"{repo}: checkout/source directory missing")
            continue
        text = source_text(source)
        if "8765" in text:
            failures.append(f"{repo}: contains obsolete port 8765")
        if port not in text:
            failures.append(f"{repo}: does not contain canonical port {port}")
    if failures:
        print("Vintage endpoint contract failed:")
        print("\n".join(f"- {failure}" for failure in failures))
        return 1
    print(f"{len(CLIENTS)} vintage clients use raw TCP port {port}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
