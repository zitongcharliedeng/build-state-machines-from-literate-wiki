#!/usr/bin/env python3
"""
check-lit-md.py — LSMW literate programming linter

Enforces structural rules on .lit.md files:

  BANNED (exit 1):
    - Code blocks without file= annotation
    - TypeScript // or /* comments inside code blocks (use prose instead)
    - @ts-ignore / @ts-nocheck / @ts-expect-error inside code blocks
    - 'as any' casts inside code blocks

  WARNED (exit 0, printed to stderr):
    - Code blocks longer than 50 lines without intervening prose
    - Files with fewer than 3 prose lines (prose-starved migration artifacts)
    - Files where first block has no prose before it (no H1 + intro paragraph)

Usage:
    python3 check-lit-md.py [--warn-only] [path/to/literate/]
    python3 check-lit-md.py literate/**/*.lit.md
"""

import re
import sys
import glob
import os
from pathlib import Path

PROSE_THRESHOLD = 3          # min non-header prose lines to avoid prose-starved warning
BLOCK_LENGTH_THRESHOLD = 50  # max code block lines before warning
EXIT_CODE = 0

def parse_blocks(content: str) -> list[dict]:
    """
    Parse a .lit.md file into a list of segments: prose or code blocks.
    Returns list of dicts: {type: 'prose'|'code', content: str, line_start: int,
                            annotation: str|None, file: str|None}
    """
    segments = []
    lines = content.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        line = lines[i]
        # Detect fenced code block opening
        m = re.match(r'^(`{3,})(.*)', line)
        if m:
            fence = m.group(1)
            annotation = m.group(2).strip()
            block_start = i + 1  # 1-indexed
            i += 1
            block_lines = []
            while i < len(lines):
                if lines[i].startswith(fence):
                    i += 1
                    break
                block_lines.append(lines[i])
                i += 1
            # Extract file= from annotation like {.typescript file=_generated/foo.ts}
            file_match = re.search(r'file=([^\s}]+)', annotation)
            file_target = file_match.group(1) if file_match else None
            segments.append({
                'type': 'code',
                'content': ''.join(block_lines),
                'line_start': block_start,
                'annotation': annotation,
                'file': file_target,
                'line_count': len(block_lines),
            })
        else:
            # Prose line — collect until next fence
            prose_lines = []
            prose_start = i + 1
            while i < len(lines) and not re.match(r'^`{3,}', lines[i]):
                prose_lines.append(lines[i])
                i += 1
            segments.append({
                'type': 'prose',
                'content': ''.join(prose_lines),
                'line_start': prose_start,
            })
    return segments


def count_prose_lines(segments: list[dict]) -> int:
    """Count non-blank, non-header prose lines across all prose segments."""
    total = 0
    for seg in segments:
        if seg['type'] != 'prose':
            continue
        for line in seg['content'].splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith('#'):
                total += 1
    return total


def check_file(path: str, warn_only: bool = False) -> list[dict]:
    """
    Check a single .lit.md file. Returns list of violations:
    {level: 'error'|'warning', rule: str, message: str, line: int}
    """
    violations = []
    content = open(path).read()
    segments = parse_blocks(content)

    # --- Rule: every code block must have file= annotation ---
    for seg in segments:
        if seg['type'] != 'code':
            continue
        annotation = seg.get('annotation', '')
        # Skip empty annotations (plain ``` blocks with no language)
        if not annotation:
            violations.append({
                'level': 'warning',
                'rule': 'no-unannotated-block',
                'message': f"Code block at line {seg['line_start']} has no annotation at all — use ``` {{.lang file=path}} or remove it",
                'line': seg['line_start'],
            })
            continue
        # Has annotation but no file=
        if 'file=' not in annotation:
            # Allow named blocks (<<name>>) which are used as code references
            if annotation.startswith('{') and '.' in annotation:
                violations.append({
                    'level': 'error',
                    'rule': 'no-code-block-without-file-annotation',
                    'message': f"Code block at line {seg['line_start']} has no file= annotation: `{annotation}`",
                    'line': seg['line_start'],
                })

    # --- Rule: no TypeScript comments inside code blocks ---
    for seg in segments:
        if seg['type'] != 'code':
            continue
        for i, line in enumerate(seg['content'].splitlines(), seg['line_start'] + 1):
            stripped = line.strip()
            # Skip URLs in comments (http:// https://)
            # Match // line comments and /* block comment openers.
            # Do NOT match bare * (CSS universal selector, JSDoc continuation lines).
            if re.match(r'^\s*(//|/\*)', line) and not re.search(r'https?://', line):
                violations.append({
                    'level': 'error',
                    'rule': 'no-ts-comments-in-lit-md',
                    'message': f"Line {i}: TypeScript comment inside code block — use prose instead: `{stripped[:60]}`",
                    'line': i,
                })

    # --- Rule: no @ts-ignore / @ts-nocheck / @ts-expect-error ---
    for seg in segments:
        if seg['type'] != 'code':
            continue
        for i, line in enumerate(seg['content'].splitlines(), seg['line_start'] + 1):
            if re.search(r'@ts-ignore|@ts-nocheck|@ts-expect-error', line):
                violations.append({
                    'level': 'error',
                    'rule': 'no-ts-suppress',
                    'message': f"Line {i}: @ts-ignore/@ts-nocheck/@ts-expect-error banned in .lit.md — fix the type error properly",
                    'line': i,
                })

    # --- Rule: no 'as any' casts ---
    for seg in segments:
        if seg['type'] != 'code':
            continue
        for i, line in enumerate(seg['content'].splitlines(), seg['line_start'] + 1):
            # as any not followed by [ (as any[] is sometimes legitimate)
            if re.search(r'\bas any(?!\[)', line):
                violations.append({
                    'level': 'error',
                    'rule': 'no-as-any',
                    'message': f"Line {i}: `as any` cast banned — add a proper type annotation",
                    'line': i,
                })

    # --- Warning: prose-starved file ---
    prose_lines = count_prose_lines(segments)
    if prose_lines < PROSE_THRESHOLD:
        violations.append({
            'level': 'warning',
            'rule': 'no-prose-starved',
            'message': f"Only {prose_lines} prose line(s) — add explanatory prose between code blocks (minimum {PROSE_THRESHOLD})",
            'line': 1,
        })

    # --- Warning: long code blocks without prose break ---
    for i, seg in enumerate(segments):
        if seg['type'] != 'code':
            continue
        if seg['line_count'] > BLOCK_LENGTH_THRESHOLD:
            # Check if next segment is prose (i.e., block is followed by explanation)
            next_is_prose = (i + 1 < len(segments) and segments[i + 1]['type'] == 'prose'
                             and len(segments[i + 1]['content'].strip()) > 20)
            if not next_is_prose:
                violations.append({
                    'level': 'warning',
                    'rule': 'long-block-without-prose',
                    'message': (f"Code block at line {seg['line_start']} is {seg['line_count']} lines "
                                f"with no prose break — split with explanatory prose"),
                    'line': seg['line_start'],
                })

    # --- Warning: no prose before first code block ---
    first_code = next((s for s in segments if s['type'] == 'code'), None)
    if first_code:
        preceding_prose = [s for s in segments
                           if s['type'] == 'prose' and s['line_start'] < first_code['line_start']]
        intro_lines = sum(
            1 for s in preceding_prose
            for l in s['content'].splitlines()
            if l.strip() and not l.strip().startswith('#')
        )
        if intro_lines == 0:
            violations.append({
                'level': 'warning',
                'rule': 'no-intro-prose',
                'message': "No prose before first code block — add an introductory paragraph explaining what this module does",
                'line': first_code['line_start'],
            })

    return violations


def main():
    args = sys.argv[1:]
    warn_only = '--warn-only' in args
    paths = [a for a in args if not a.startswith('--')]

    if not paths:
        # Default: search current directory
        paths = glob.glob('literate/**/*.lit.md', recursive=True)
        if not paths:
            paths = glob.glob('**/*.lit.md', recursive=True)

    if not paths:
        print("No .lit.md files found", file=sys.stderr)
        sys.exit(0)

    total_errors = 0
    total_warnings = 0
    files_with_violations = 0

    for path in sorted(paths):
        violations = check_file(path, warn_only)
        errors = [v for v in violations if v['level'] == 'error']
        warnings = [v for v in violations if v['level'] == 'warning']

        if violations:
            files_with_violations += 1
            print(f"\n{path}:")
            for v in sorted(violations, key=lambda x: x['line']):
                level = 'ERROR' if v['level'] == 'error' else 'WARN '
                print(f"  {level} [{v['rule']}] line {v['line']}: {v['message']}")

        total_errors += len(errors)
        total_warnings += len(warnings)

    print(f"\n{'='*60}")
    print(f"Checked {len(paths)} files: {total_errors} errors, {total_warnings} warnings")

    if total_errors > 0 and not warn_only:
        print(f"FAILED: {total_errors} error(s) must be fixed")
        sys.exit(1)
    elif total_errors > 0:
        print(f"WARN-ONLY: {total_errors} error(s) found (not blocking)")
    else:
        print("PASSED")


if __name__ == '__main__':
    main()
