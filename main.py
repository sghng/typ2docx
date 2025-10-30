#! /usr/bin/env python3

import argparse
import json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", help="Entry point to the Typst project")
    args = parser.parse_args()

    try:
        from extract import extract_equations
    except Exception as e:
        raise SystemExit(
            "Failed to import Rust extension 'extract'.\n"
            "Build and install the extension locally, e.g.:\n\n"
            "  uv run maturin develop\n\n"
            f"Original error: {e}"
        )

    equations = extract_equations(args.path)
    print(json.dumps(equations))


if __name__ == "__main__":
    main()
