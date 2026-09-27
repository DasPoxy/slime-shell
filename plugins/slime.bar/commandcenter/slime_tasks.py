#!/usr/bin/env python3
"""Slime-Tasks: the command centre's todo / task-log / progress suite.

Everything lives as plain markdown in one folder (default ~/Documents/Slime-Notes),
so any notes app (Envy, Obsidian, a text editor) can read and edit it too:

  Slime-Notes/
    Todos/<id>.md      one per top-level todo: front matter + "- [ ]" sub-todos
    Logs/<id>.md       that todo's task log: "## <time> · <who>" entries
    Archive/           archived todos (and Archive/Logs/ their logs)
    .slime/groups.json group colours
    .slime/trash/      deleted todos, just in case

A todo file:

    ---
    group: Slime Shell
    done: false
    created: 2026-09-26 13:40
    ---
    # Overhaul the tasks tab

    - [ ] a sub-todo
    - [/] one being worked on
    - [x] one that's finished

Sub-todo states: todo "[ ]", doing "[/]", done "[x]".

Commands (all print JSON; errors go to stderr with exit status 1):

  list [--archived]                 every todo with its sub-todos
  add TITLE [--group G]             new top-level todo -> {"id"}
  rename ID TITLE
  done ID true|false                mark a top-level todo finished (or not)
  delete ID                         moves it (and its log) to .slime/trash
  sub-add ID TEXT
  sub-edit ID N TEXT
  sub-set ID N todo|doing|done [--expect TEXT]
  sub-delete ID N
  sub-move ID N TO                  reorder sub-todos
  order ID [ID ...]                 put todos in this order (others keep theirs, after)
  start ID N [NOTE] [--by WHO]      sub-todo -> doing, and log it
  finish ID N [NOTE] [--by WHO]     sub-todo -> done, and log it
  group ID GROUP                    "" ungroups
  group-color GROUP #RRGGBB
  log ID MESSAGE [--by WHO]         append a task-log entry
  log-show ID                       -> {"entries": [{time, by, text}]}
  archive ID / unarchive ID
  search QUERY [--archived]         titles and sub-todos containing QUERY
  find TEXT                         todos whose title contains TEXT (for agents)
  folder [PATH]                     show / set the notes folder

N is a sub-todo's 0-based position. Agents: `find` the todo, then `start` a
sub-todo when you pick it up, `log` progress and output as you go, and
`finish` it when it's done — the Task Log tab shows it all live.
"""
import datetime as dt
import fcntl
import json
import os
import re
import shutil
import sys
import tempfile

CONF = os.path.expanduser("~/.config/omarchy/slime-shell/slime-tasks.json")
DEFAULT_FOLDER = "~/Documents/Slime-Notes"
SUB = re.compile(r"^(\s*)[-*+]\s+\[([ xX/])\]\s+(.*)$")
STATE_MARK = {"todo": " ", "doing": "/", "done": "x"}
MARK_STATE = {" ": "todo", "/": "doing", "x": "done", "X": "done"}
PALETTE = ["#e0406a", "#40a0e0", "#e0b040", "#60c060", "#a060e0", "#e07040", "#40c0b0", "#d060a0"]


class Fail(Exception):
    pass


# ---- folder -----------------------------------------------------------------

def folder():
    try:
        with open(CONF) as f:
            p = json.load(f).get("folder")
        if p:
            return os.path.expanduser(p)
    except (OSError, ValueError):
        pass
    return os.path.expanduser(DEFAULT_FOLDER)


def ensure(root):
    for sub in ("Todos", "Logs", "Archive", "Archive/Logs", ".slime", ".slime/trash"):
        os.makedirs(os.path.join(root, sub), exist_ok=True)
    readme = os.path.join(root, "README.md")
    if not os.path.exists(readme):
        write(readme, "# Slime-Notes\n\nTodos and task logs for Slime Shell's command centre "
              "(Tasks tab). Plain markdown — edit them here or in any notes app.\n\n"
              "Agents and scripts: use `slime-tasks` (see `slime-tasks --help`).\n")


def write(path, text):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


class Lock:
    """One writer at a time (the tab and an agent may both be editing)."""
    def __init__(self, root):
        self.path = os.path.join(root, ".slime", "lock")

    def __enter__(self):
        self.f = open(self.path, "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


# ---- todo files -------------------------------------------------------------

def slug(title, taken):
    base = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:48] or "todo"
    s, n = base, 2
    while s in taken:
        s, n = f"{base}-{n}", n + 1
    return s


def parse(path):
    with open(path) as f:
        lines = f.read().split("\n")
    meta, body_start = {}, 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                body_start = i + 1
                break
            k, _, v = lines[i].partition(":")
            meta[k.strip()] = v.strip()
    title, subs = "", []
    for i in range(body_start, len(lines)):
        line = lines[i]
        if not title and line.startswith("# "):
            title = line[2:].strip()
            continue
        m = SUB.match(line)
        if m:
            subs.append({"line": i, "state": MARK_STATE[m.group(2)], "text": m.group(3), "indent": len(m.group(1))})
    return {"meta": meta, "title": title, "subs": subs, "lines": lines}


def render(todo):
    meta = todo["meta"]
    out = ["---"] + [f"{k}: {v}" for k, v in meta.items() if v != ""] + ["---", f"# {todo['title']}", ""]
    for s in todo["subs"]:
        out.append(f"{' ' * s.get('indent', 0)}- [{STATE_MARK[s['state']]}] {s['text']}")
    return "\n".join(out) + "\n"


def todo_path(root, tid, archived=False):
    p = os.path.join(root, "Archive" if archived else "Todos", tid + ".md")
    if not os.path.exists(p):
        raise Fail(f"no todo '{tid}'" + (" in the archive" if archived else ""))
    return p


def log_path(root, tid, archived=False):
    return os.path.join(root, "Archive/Logs" if archived else "Logs", tid + ".md")


def load(root, tid, archived=False):
    p = todo_path(root, tid, archived)
    t = parse(p)
    t["path"] = p
    return t


def save(t):
    write(t["path"], render(t))


def now():
    return dt.datetime.now().strftime("%Y-%m-%d %H:%M")


def groups(root):
    try:
        with open(os.path.join(root, ".slime", "groups.json")) as f:
            return json.load(f).get("groups", {})
    except (OSError, ValueError):
        return {}


def save_groups(root, g):
    write(os.path.join(root, ".slime", "groups.json"), json.dumps({"groups": g}, indent=2) + "\n")


def log_entries(root, tid, archived=False):
    p = log_path(root, tid, archived)
    if not os.path.exists(p):
        return []
    entries, cur = [], None
    with open(p) as f:
        for line in f.read().split("\n"):
            m = re.match(r"^## (\d{4}-\d\d-\d\d \d\d:\d\d)(?: · (.*))?$", line)
            if m:
                cur = {"time": m.group(1), "by": m.group(2) or "", "text": ""}
                entries.append(cur)
            elif cur is not None:
                cur["text"] += line + "\n"
    for e in entries:
        e["text"] = e["text"].strip()
    return entries


def append_log(root, tid, message, by="", archived=False):
    p = log_path(root, tid, archived)
    if not os.path.exists(p):
        title = load(root, tid, archived)["title"]
        head = f"# Log — {title}\n"
    else:
        with open(p) as f:
            head = f.read().rstrip("\n") + "\n"
    write(p, head + f"\n## {now()}" + (f" · {by}" if by else "") + f"\n{message.strip()}\n")


def summary(root, tid, archived=False):
    t = load(root, tid, archived)
    subs = [{"i": i, "state": s["state"], "text": s["text"]} for i, s in enumerate(t["subs"])]
    lp = log_path(root, tid, archived)
    return {
        "id": tid,
        "title": t["title"] or tid,
        "group": t["meta"].get("group", ""),
        "done": t["meta"].get("done", "false") == "true",
        "created": t["meta"].get("created", ""),
        "order": int(t["meta"].get("order", "0") or 0),
        "archived": archived,
        "mtime": os.path.getmtime(t["path"]),
        "subs": subs,
        "counts": {k: sum(1 for s in subs if s["state"] == k) for k in ("todo", "doing", "done")},
        "logMtime": os.path.getmtime(lp) if os.path.exists(lp) else 0,
        "logCount": len(log_entries(root, tid, archived)),
    }


def all_ids(root, archived=False):
    d = os.path.join(root, "Archive" if archived else "Todos")
    return sorted(f[:-3] for f in os.listdir(d) if f.endswith(".md") and not f.startswith("."))


def sub_at(t, n):
    n = int(n)
    if not 0 <= n < len(t["subs"]):
        raise Fail(f"'{t['title']}' has no sub-todo {n}")
    return t["subs"][n]


# ---- commands ---------------------------------------------------------------

def run(argv):
    args, opts = [], {}
    it = iter(argv)
    for a in it:
        if a.startswith("--") and a not in ("--archived",):
            opts[a[2:]] = next(it, "")
        elif a == "--archived":
            opts["archived"] = True
        else:
            args.append(a)
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        return None
    cmd, rest = args[0], args[1:]

    if cmd == "folder":
        if rest:
            os.makedirs(os.path.dirname(CONF), exist_ok=True)
            write(CONF, json.dumps({"folder": rest[0]}, indent=2) + "\n") if rest[0] else (os.path.exists(CONF) and os.remove(CONF))
        ensure(folder())
        return {"folder": folder()}

    root = folder()
    ensure(root)
    archived = bool(opts.get("archived"))

    if cmd == "list":
        todos = [summary(root, i, archived) for i in all_ids(root, archived)]
        # hand-set order first (0 = never ordered), then oldest first
        todos.sort(key=lambda t: (t["order"] or 10**9, t["created"] or ""))
        return {"folder": root, "groups": groups(root), "todos": todos}
    if cmd == "log-show":
        return {"entries": log_entries(root, rest[0], archived)}
    if cmd in ("search", "find"):
        q = " ".join(rest).lower()
        out = []
        for arch in ([False, True] if cmd == "search" and archived else [archived]):
            for i in all_ids(root, arch):
                s = summary(root, i, arch)
                hit = q in s["title"].lower() or (cmd == "search" and any(q in x["text"].lower() for x in s["subs"]))
                if hit:
                    out.append(s)
        return {"todos": out}

    with Lock(root):
        if cmd == "add":
            title = " ".join(rest).strip()
            if not title:
                raise Fail("a todo needs a title")
            tid = slug(title, set(all_ids(root)) | set(all_ids(root, True)))
            meta = {"group": opts.get("group", ""), "done": "false", "created": now()}
            write(os.path.join(root, "Todos", tid + ".md"), render({"meta": meta, "title": title, "subs": []}))
            if meta["group"] and meta["group"] not in groups(root):
                g = groups(root)
                g[meta["group"]] = {"color": PALETTE[len(g) % len(PALETTE)]}
                save_groups(root, g)
            return {"id": tid}

        tid = rest[0] if rest else ""
        if cmd == "unarchive":
            src, lsrc = todo_path(root, tid, True), log_path(root, tid, True)
            shutil.move(src, os.path.join(root, "Todos", tid + ".md"))
            if os.path.exists(lsrc):
                shutil.move(lsrc, log_path(root, tid))
            t = load(root, tid)
            t["meta"]["done"] = "false"
            save(t)
            return {"id": tid}
        if cmd == "order":
            ids = [i for i in rest if i in set(all_ids(root))]
            rest_ids = [i for i in all_ids(root) if i not in ids]
            for n, i in enumerate(ids + rest_ids, 1):
                t = load(root, i)
                if t["meta"].get("order") != str(n):
                    t["meta"]["order"] = str(n)
                    save(t)
            return {"order": ids + rest_ids}
        if cmd == "group-color":
            g = groups(root)
            g.setdefault(rest[0], {})["color"] = rest[1]
            save_groups(root, g)
            return {"group": rest[0]}

        t = load(root, tid, archived)
        by = opts.get("by", "")
        if cmd == "rename":
            t["title"] = " ".join(rest[1:]).strip() or t["title"]
        elif cmd == "done":
            t["meta"]["done"] = "true" if rest[1] == "true" else "false"
        elif cmd == "delete":
            trash = os.path.join(root, ".slime", "trash", dt.datetime.now().strftime("%Y%m%d-%H%M%S-") + tid)
            os.makedirs(trash, exist_ok=True)
            shutil.move(t["path"], trash)
            if os.path.exists(log_path(root, tid, archived)):
                shutil.move(log_path(root, tid, archived), os.path.join(trash, "log.md"))
            return {"deleted": tid}
        elif cmd == "archive":
            shutil.move(t["path"], os.path.join(root, "Archive", tid + ".md"))
            if os.path.exists(log_path(root, tid)):
                shutil.move(log_path(root, tid), log_path(root, tid, True))
            return {"archived": tid}
        elif cmd == "group":
            name = " ".join(rest[1:]).strip()
            t["meta"]["group"] = name
            if name and name not in groups(root):
                g = groups(root)
                g[name] = {"color": PALETTE[len(g) % len(PALETTE)]}
                save_groups(root, g)
        elif cmd == "sub-add":
            text = " ".join(rest[1:]).strip()
            if not text:
                raise Fail("a sub-todo needs some text")
            t["subs"].append({"state": "todo", "text": text, "indent": 0})
        elif cmd == "sub-edit":
            sub_at(t, rest[1])["text"] = " ".join(rest[2:]).strip()
        elif cmd == "sub-delete":
            s = sub_at(t, rest[1])
            t["subs"].remove(s)
        elif cmd == "sub-move":
            s = sub_at(t, rest[1])
            t["subs"].remove(s)
            t["subs"].insert(max(0, min(len(t["subs"]), int(rest[2]))), s)
        elif cmd in ("sub-set", "start", "finish"):
            s = sub_at(t, rest[1])
            if opts.get("expect") and s["text"] != opts["expect"]:
                raise Fail(f"sub-todo {rest[1]} changed meanwhile (it now reads '{s['text']}')")
            state = {"start": "doing", "finish": "done"}.get(cmd) or rest[2]
            if state not in STATE_MARK:
                raise Fail("state is todo, doing or done")
            s["state"] = state
            if cmd in ("start", "finish"):
                note = " ".join(rest[2:]).strip()
                verb = "Started" if cmd == "start" else "Finished"
                save(t)
                append_log(root, tid, f"{verb}: {s['text']}" + (f"\n\n{note}" if note else ""), by, archived)
                return summary(root, tid, archived)
        elif cmd == "log":
            append_log(root, tid, " ".join(rest[1:]), by, archived)
            return {"logged": tid}
        else:
            raise Fail(f"unknown command '{cmd}' (see --help)")
        save(t)
        return summary(root, tid, archived)


def main():
    try:
        out = run(sys.argv[1:])
    except Fail as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
    except (IndexError, ValueError):
        print("missing or bad arguments (see --help)", file=sys.stderr)
        sys.exit(1)
    if out is not None:
        print(json.dumps(out))


if __name__ == "__main__":
    main()
