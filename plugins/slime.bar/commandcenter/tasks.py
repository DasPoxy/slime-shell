#!/usr/bin/env python3
"""Envy tasks for the command centre's Tasks tab.

  tasks.py list                         -> JSON list of every "- [ ]"/"- [x]" task
  tasks.py toggle FILE LINE EXPECTED    -> flip that checkbox

The vault comes from ~/.config/envy/config.md (`vault = "..."`), honouring
`include_subfolders`. A toggle only writes if line LINE of FILE still reads
EXPECTED exactly, so an edit made in Envy meanwhile is never clobbered.
"""
import json
import os
import re
import sys
import tempfile

TASK = re.compile(r"^(\s*[-*+]\s+\[)([ xX])(\]\s+)(.*)$")


def vault_settings():
    vault, subfolders = "~/Documents/Envy", False
    try:
        with open(os.path.expanduser("~/.config/envy/config.md")) as f:
            for line in f:
                m = re.match(r'\s*vault\s*=\s*"([^"]+)"', line)
                if m:
                    vault = m.group(1)
                m = re.match(r"\s*include_subfolders\s*=\s*(true|false)", line)
                if m:
                    subfolders = m.group(1) == "true"
    except OSError:
        pass
    return os.path.expanduser(vault), subfolders


def notes(vault, subfolders):
    for root, dirs, files in os.walk(vault):
        dirs[:] = [d for d in dirs if not d.startswith(".")] if subfolders else []
        for name in sorted(files):
            if name.endswith(".md"):
                yield os.path.join(root, name)


def list_tasks():
    vault, subfolders = vault_settings()
    out = []
    for path in notes(vault, subfolders):
        try:
            with open(path, encoding="utf-8") as f:
                lines = f.read().split("\n")
        except (OSError, UnicodeDecodeError):
            continue
        for i, line in enumerate(lines):
            m = TASK.match(line)
            if not m or not m.group(4).strip():
                continue
            out.append({
                "file": path,
                "note": os.path.splitext(os.path.relpath(path, vault))[0],
                "line": i,
                "raw": line,
                "text": m.group(4).strip(),
                "done": m.group(2) != " ",
                "mtime": os.path.getmtime(path),
            })
    print(json.dumps(out))


def toggle(path, line_no, expected):
    vault, _ = vault_settings()
    real = os.path.realpath(path)
    if not real.startswith(os.path.realpath(vault) + os.sep):
        sys.exit("refusing to edit outside the vault")
    with open(real, encoding="utf-8") as f:
        lines = f.read().split("\n")
    if line_no >= len(lines) or lines[line_no] != expected:
        sys.exit("task changed on disk; not toggled")
    m = TASK.match(expected)
    if not m:
        sys.exit("not a task line")
    lines[line_no] = m.group(1) + (" " if m.group(2) != " " else "x") + m.group(3) + m.group(4)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(real), prefix=".slime-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.replace(tmp, real)
    print("ok")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "list":
        list_tasks()
    elif len(sys.argv) == 5 and sys.argv[1] == "toggle":
        toggle(sys.argv[2], int(sys.argv[3]), sys.argv[4])
    else:
        sys.exit(__doc__)
