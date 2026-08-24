#!/usr/bin/env python3

"""Apply repository-only package sections to a generated APT Packages file."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


ALLOWED_SECTIONS = {"依赖插件", "美化插件", "功能插件"}


def fail(message: str) -> "NoReturn":
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(65)


def load_mapping(path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}

    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeError) as error:
        fail(f"cannot read section mapping {path}: {error}")

    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        filename, separator, section = raw_line.partition("\t")
        filename = filename.strip().replace("\\", "/")
        section = section.strip()

        if not separator or not filename or not section:
            fail(f"invalid mapping at {path}:{line_number}; expected Filename<TAB>Section")
        if not filename.startswith("debs/") or not filename.endswith(".deb"):
            fail(f"invalid DEB path at {path}:{line_number}: {filename}")
        if section not in ALLOWED_SECTIONS:
            allowed = ", ".join(sorted(ALLOWED_SECTIONS))
            fail(f"unsupported section at {path}:{line_number}: {section} (allowed: {allowed})")
        if filename in mapping:
            fail(f"duplicate section mapping at {path}:{line_number}: {filename}")

        mapping[filename] = section

    if not mapping:
        fail(f"section mapping is empty: {path}")

    return mapping


def field_value(lines: list[str], field_name: str) -> str | None:
    prefix = f"{field_name}:"
    for line in lines:
        if line.startswith(prefix):
            return line[len(prefix) :].strip()
    return None


def set_section(lines: list[str], section: str) -> list[str]:
    for index, line in enumerate(lines):
        if line.startswith("Section:"):
            lines[index] = f"Section: {section}"
            return lines

    for index, line in enumerate(lines):
        if line.startswith("Description:"):
            lines.insert(index, f"Section: {section}")
            return lines

    lines.append(f"Section: {section}")
    return lines


def apply_sections(mapping: dict[str, str], packages_path: Path) -> None:
    try:
        packages_text = packages_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        fail(f"cannot read Packages file {packages_path}: {error}")

    raw_stanzas = [stanza for stanza in packages_text.split("\n\n") if stanza.strip()]
    if not raw_stanzas:
        fail(f"Packages file is empty: {packages_path}")

    output_stanzas: list[str] = []
    used_filenames: set[str] = set()
    missing_filenames: list[str] = []

    for raw_stanza in raw_stanzas:
        lines = raw_stanza.splitlines()
        filename = field_value(lines, "Filename")
        package_id = field_value(lines, "Package") or "<unknown>"

        if not filename:
            fail(f"package stanza has no Filename field: {package_id}")

        filename = filename.replace("\\", "/")
        section = mapping.get(filename)
        if section is None:
            missing_filenames.append(filename)
            output_stanzas.append(raw_stanza)
            continue

        used_filenames.add(filename)
        output_stanzas.append("\n".join(set_section(lines, section)))
        print(f"classified: {package_id} -> {section}")

    if missing_filenames:
        formatted = "\n  ".join(sorted(missing_filenames))
        fail(
            "these packages have no category in config/sections.tsv; "
            f"use the upload BAT or add them manually:\n  {formatted}"
        )

    unused_filenames = sorted(set(mapping) - used_filenames)
    for filename in unused_filenames:
        print(f"warning: unused section mapping: {filename}", file=sys.stderr)

    packages_path.write_text("\n\n".join(output_stanzas) + "\n", encoding="utf-8")
    print(f"applied sections to {len(output_stanzas)} package(s)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mapping", type=Path)
    parser.add_argument("packages", type=Path)
    args = parser.parse_args()

    apply_sections(load_mapping(args.mapping), args.packages)


if __name__ == "__main__":
    main()
