#!/usr/bin/env python3
"""Add package access to top-level Swift declarations (not locals)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Sources" / "BackTrackCore"
SKIP = ("private ", "fileprivate ", "package ", "public ", "open ")

def mark_line(line: str) -> str:
    stripped = line.lstrip()
    indent = line[: len(line) - len(stripped)]
    if not stripped or stripped.startswith("//"):
        return line
    if any(stripped.startswith(p) for p in SKIP):
        return line
    for kw in ("struct ", "enum ", "class ", "final class ", "protocol ", "extension "):
        if stripped.startswith(kw):
            return f"{indent}package {stripped}"
    if stripped.startswith("package protocol "):
        return line
    # Type members only at exactly 4 spaces — skip locals (8+ spaces).
    if indent == "    ":
        if stripped.startswith("@Published var "):
            return f"{indent}@Published package var {stripped[len('@Published var '):]}"
        if stripped.startswith("static let "):
            return f"{indent}package static let {stripped[len('static let '):]}"
        if stripped.startswith("static var "):
            return f"{indent}package static var {stripped[len('static var '):]}"
        if stripped.startswith("var ") and "static" not in stripped:
            return f"{indent}package var {stripped[len('var '):]}"
        if stripped.startswith("let ") and "static" not in stripped:
            return f"{indent}package let {stripped[len('let '):]}"
        if stripped.startswith("func ") or stripped.startswith("static func "):
            return f"{indent}package {stripped}"
        if stripped.startswith("init("):
            return f"{indent}package {stripped}"
    return line

for path in sorted(ROOT.rglob("*.swift")):
    if path.name in ("ContentStore.swift",):
        continue
    text = path.read_text()
    path.write_text("\n".join(mark_line(l) for l in text.splitlines()) + "\n")

print("Marked", len(list(ROOT.rglob("*.swift"))), "Core files")
