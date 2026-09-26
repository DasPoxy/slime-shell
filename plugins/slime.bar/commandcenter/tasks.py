#!/usr/bin/env python3
"""Markdown tasks for the command centre's Tasks tab.

  tasks.py list                         -> {"folder", "source", "tasks": [...]}
  tasks.py toggle FILE LINE EXPECTED    -> flip that checkbox
  tasks.py set-folder PATH [SUBFOLDERS] -> use PATH ("" = back to automatic)

Works with any folder of markdown notes. The folder is, in order:
  1. ~/.config/omarchy/slime-shell/tasks.json  {"folder": "...", "subfolders": true}
  2. Envy's vault (~/.config/envy/config.md: vault = "...", include_subfolders)
  3. ~/Notes or ~/Documents/Notes, if either exists
A task is any "- [ ]" / "- [x]" (or * / +) line. A toggle only writes if line
LINE of FILE still reads EXPECTED exactly, so an edit made meanwhile in your
notes app is never clobbered.
"""
import json
import os
import re
import sys
import tempfile

TASK = re.compile(r"^(\s*[-*+]\s+\[)([ xX])(\]\s+)(.*)$")


SLIME = os.path.expanduser("~/.config/omarchy/slime-shell/tasks.json")


def vault_settings():
    """(folder, subfolders, source) — see the module docstring for the order."""
    try:
        with open(SLIME) as f:
            conf = json.load(f)
        if conf.get("folder"):
            return os.path.expanduser(conf["folder"]), bool(conf.get("subfolders", True)), "custom"
    except (OSError, ValueError):
        pass
    envy = envy_settings()
    if envy:
        return envy[0], envy[1], "envy"
    for guess in ("~/Notes", "~/Documents/Notes"):
        if os.path.isdir(os.path.expanduser(guess)):
            return os.path.expanduser(guess), True, "default"
    return "", False, "none"


def envy_settings():
    vault, subfolders, found = "~/Documents/Envy", False, False
    try:
        with open(os.path.expanduser("~/.config/envy/config.md")) as f:
            for line in f:
                m = re.match(r'\s*vault\s*=\s*"([^"]+)"', line)
                if m:
                    vault, found = m.group(1), True
                m = re.match(r"\s*include_subfolders\s*=\s*(true|false)", line)
                if m:
                    subfolders = m.group(1) == "true"
    except OSError:
        return None
    return (os.path.expanduser(vault), subfolders) if found else None


def notes(vault, subfolders):
    for root, dirs, files in os.walk(vault):
        dirs[:] = [d for d in dirs if not d.startswith(".")] if subfolders else []
        for name in sorted(files):
            if name.endswith(".md"):
                yield os.path.join(root, name)


def list_tasks():
    vault, subfolders, source = vault_settings()
    out = []
    if not vault or not os.path.isdir(vault):
        print(json.dumps({"folder": vault, "source": source, "tasks": []}))
        return
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
    print(json.dumps({"folder": vault, "source": source, "tasks": out}))


def toggle(path, line_no, expected):
    vault, _, _ = vault_settings()
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


def set_folder(path, subfolders=True):
    os.makedirs(os.path.dirname(SLIME), exist_ok=True)
    with open(SLIME, "w") as f:
        json.dump({"folder": path, "subfolders": subfolders}, f, indent=2)
    print("ok")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "list":
        list_tasks()
    elif len(sys.argv) >= 3 and sys.argv[1] == "set-folder":
        set_folder(sys.argv[2], len(sys.argv) < 4 or sys.argv[3] != "false")
    elif len(sys.argv) == 5 and sys.argv[1] == "toggle":
        toggle(sys.argv[2], int(sys.argv[3]), sys.argv[4])
    else:
        sys.exit(__doc__)
