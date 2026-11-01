"""Prepare one fresh task-owned workspace; never overwrite an existing trial."""
import argparse
from pathlib import Path

from common import fetch, prepare


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    args.work.mkdir(exist_ok=False)
    fetch(args.work)
    prepare(args.work)
