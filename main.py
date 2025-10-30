#! /usr/bin/env python3

import argparse
import json

from extract import extract  # ty: ignore[unresolved-import]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", help="Entry point to the Typst project")
    args = parser.parse_args()
    equations = extract(args.path)
    print(json.dumps(equations))


if __name__ == "__main__":
    main()
