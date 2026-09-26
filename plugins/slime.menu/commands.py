#!/usr/bin/env python3
"""Omarchy menu actions, flattened for the Slime launcher's quick commands.

Reads the default Omarchy menu and the user's extension (same merge as the
Omarchy menu: user ids override), keeps rows that run an action, drops rows
whose `when` condition fails (checked in parallel, 2 s each), and prints JSON:
  [{"id", "label", "path", "icon", "action", "keywords"}]
"""
import concurrent.futures
import json
import os
import re
import subprocess

OMARCHY = os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")
SOURCES = [os.path.join(OMARCHY, "default/omarchy/omarchy-menu.jsonc"),
           os.path.expanduser("~/.config/omarchy/extensions/omarchy-menu.jsonc")]


def parse_jsonc(text):
    out, i, n = [], 0, len(text)
    while i < n:                       # strip comments outside strings
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1]); i = j + 1
        elif text.startswith("//", i):
            i = text.find("\n", i); i = n if i < 0 else i
        elif text.startswith("/*", i):
            i = text.find("*/", i); i = n if i < 0 else i + 2
        else:
            out.append(c); i += 1
    cleaned = re.sub(r",(\s*[}\]])", r"\1", "".join(out))
    return json.loads(cleaned or "{}")


def main():
    items = {}
    for path in SOURCES:
        try:
            with open(path, encoding="utf-8") as f:
                items.update(parse_jsonc(f.read()))
        except (OSError, ValueError):
            pass
    rows = []
    for key, it in items.items():
        if not isinstance(it, dict) or not it.get("action"):
            continue
        parts = key.split(".")
        trail = [items.get(".".join(parts[:k]), {}).get("label", parts[k - 1]) for k in range(1, len(parts))]
        rows.append({"id": key, "label": it.get("label", parts[-1]), "path": " › ".join(trail),
                     "icon": it.get("icon", ""), "action": it["action"], "when": it.get("when", ""),
                     "keywords": " ".join([it.get("description", ""), it.get("keywords", ""),
                                           " ".join(it.get("aliases", []))]).strip()})

    def ok(row):
        if not row["when"]:
            return True
        try:
            return subprocess.run(["bash", "-c", row["when"]], capture_output=True, timeout=2).returncode == 0
        except subprocess.TimeoutExpired:
            return False

    with concurrent.futures.ThreadPoolExecutor(16) as pool:
        keep = list(pool.map(ok, rows))
    out = [{k: v for k, v in r.items() if k != "when"} for r, k in zip(rows, keep) if k]
    print(json.dumps(out))


if __name__ == "__main__":
    main()
