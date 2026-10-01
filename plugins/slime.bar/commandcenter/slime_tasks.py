#!/usr/bin/env python3
"""Slime-Tasks: the command centre's todo / task-log / progress suite.

Everything lives as plain markdown in one folder (default ~/Documents/Slime-Notes),
so any notes app (Envy, Obsidian, a text editor) can read and edit it too:

  Slime-Notes/
    Todos/<id>.md      one per top-level todo: front matter + "- [ ]" sub-todos
    Logs/<id>.md       that todo's task log: "## <time> · <who>" entries
    Archive/           archived todos (and Archive/Logs/ their logs)
    Attachments/<id>/  pictures hung under that todo's sub-todos
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
  sub-image-add ID N FILE           copy a picture to Attachments/ID/ and attach it to sub-todo N
  sub-image-remove ID N K           take picture K off sub-todo N (the file goes to the trash)
  sub-move ID N TO                  reorder sub-todos
  order ID [ID ...]                 put todos in this order (others keep theirs, after)
  start ID N [NOTE] [--by WHO]      sub-todo -> doing, and log it
  finish ID N [NOTE] [--by WHO]     sub-todo -> done, and log it
  group ID GROUP                    "" ungroups
  group-color GROUP #RRGGBB
  group-order GROUP [GROUP ...]     put groups in this order
  group-delete GROUP                remove a group (its todos become ungrouped)
  group-rename OLD NEW              rename a group (keeps its colour and place)
  super-set GROUP SUPER             put a group in a super group ("" takes it out)
  super-rename OLD NEW              rename a super group
  super-delete SUPER                remove a super group (its groups are kept)
  super-order SUPER [SUPER ...]     put super groups in this order
  group-archive GROUP               archive every todo in a group
  group-restore GROUP               restore every archived todo in a group
  super-archive SUPER               archive every todo in a super group's groups
  super-restore SUPER               restore every archived todo in a super group's groups
  log ID MESSAGE [--by WHO] [--sub N]  append a task-log entry (about sub-todo N)
  log-show ID                       -> {"entries": [{n, time, by, sub, text}]}
  log-all                           every todo's log, tagged with id, title, group and super
  log-edit ID N TEXT [--expect OLD]  rewrite entry N's text (0 = oldest)
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
import urllib.parse
import shutil
import sys
import tempfile

CONF = os.path.expanduser("~/.config/omarchy/slime-shell/slime-tasks.json")
DEFAULT_FOLDER = "~/Documents/Slime-Notes"
SUB = re.compile(r"^(\s*)[-*+]\s+\[([ xX/])\]\s+(.*)$")
# a picture under a sub-todo: an indented markdown image line after it
IMG = re.compile(r"^(\s+)!\[([^\]]*)\]\(([^)]+)\)\s*$")
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".svg")
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
            subs.append({"line": i, "state": MARK_STATE[m.group(2)], "text": m.group(3), "indent": len(m.group(1)), "images": []})
            continue
        m = IMG.match(line)
        if m and subs and len(m.group(1)) > subs[-1]["indent"]:
            subs[-1]["images"].append({"name": m.group(2), "path": m.group(3)})
    return {"meta": meta, "title": title, "subs": subs, "lines": lines}


def render(todo):
    meta = todo["meta"]
    out = ["---"] + [f"{k}: {v}" for k, v in meta.items() if v != ""] + ["---", f"# {todo['title']}", ""]
    for s in todo["subs"]:
        out.append(f"{' ' * s.get('indent', 0)}- [{STATE_MARK[s['state']]}] {s['text']}")
        for im in s.get("images", []):
            out.append(f"{' ' * (s.get('indent', 0) + 2)}![{im['name']}]({im['path']})")
    return "\n".join(out) + "\n"


def check_id(tid):
    # ids are slugs; anything else (a "/", "..") could reach outside the folder
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", tid or "") or ".." in tid:
        raise Fail(f"'{tid}' isn't a todo id")
    return tid


def todo_path(root, tid, archived=False):
    check_id(tid)
    p = os.path.join(root, "Archive" if archived else "Todos", tid + ".md")
    if not os.path.exists(p):
        raise Fail(f"no todo '{tid}'" + (" in the archive" if archived else ""))
    return p


def log_path(root, tid, archived=False):
    check_id(tid)
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


def group_order(root):
    try:
        with open(os.path.join(root, ".slime", "groups.json")) as f:
            return json.load(f).get("order", [])
    except (OSError, ValueError):
        return []


def group_file(root):
    try:
        with open(os.path.join(root, ".slime", "groups.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def supers(root):
    """Super groups: {name: {color}} (a group names its super in groups[g]["super"])."""
    return group_file(root).get("supers", {})


def super_order(root):
    return group_file(root).get("superOrder", [])


def save_groups(root, g, order=None, sup=None, sorder=None):
    write(os.path.join(root, ".slime", "groups.json"),
          json.dumps({"groups": g, "order": group_order(root) if order is None else order,
                      "supers": supers(root) if sup is None else sup,
                      "superOrder": super_order(root) if sorder is None else sorder}, indent=2) + "\n")


def log_entries(root, tid, archived=False):
    p = log_path(root, tid, archived)
    if not os.path.exists(p):
        return []
    entries, cur = [], None
    with open(p) as f:
        for line in f.read().split("\n"):
            m = re.match(r"^## (\d{4}-\d\d-\d\d \d\d:\d\d)(?: · (.*))?$", line)
            if m:
                by, _, sub = (m.group(2) or "").partition(" · ")
                cur = {"n": len(entries), "time": m.group(1), "by": by.strip(), "sub": sub.strip(), "text": ""}
                entries.append(cur)
            elif cur is not None:
                cur["text"] += line + "\n"
    for e in entries:
        e["text"] = e["text"].strip()
        # older entries: the sub-todo is named in "Started: …" / "Finished: …"
        if not e["sub"]:
            m = re.match(r"^(?:Started|Finished): (.*)", e["text"])
            if m:
                e["sub"] = m.group(1).split("\n")[0].strip()
    return entries


LOG_HEAD = re.compile(r"^## \d{4}-\d\d-\d\d \d\d:\d\d(?: · .*)?$")


def edit_log(root, tid, n, text, expect=None, archived=False):
    """Replace the body of entry n (0 = oldest), keeping its heading."""
    p = log_path(root, tid, archived)
    if not os.path.exists(p):
        raise Fail(f"'{tid}' has no log")
    with open(p) as f:
        lines = f.read().split("\n")
    heads = [i for i, l in enumerate(lines) if LOG_HEAD.match(l)]
    if not 0 <= n < len(heads):
        raise Fail(f"the log has no entry {n}")
    start, end = heads[n] + 1, heads[n + 1] if n + 1 < len(heads) else len(lines)
    if expect is not None and "\n".join(lines[start:end]).strip() != expect.strip():
        raise Fail("that log entry changed meanwhile — reopen it and try again")
    body = text.strip().split("\n") + [""]
    lines[start:end] = body
    write(p, "\n".join(lines).rstrip("\n") + "\n")


def append_log(root, tid, message, by="", archived=False, sub=""):
    p = log_path(root, tid, archived)
    if not os.path.exists(p):
        title = load(root, tid, archived)["title"]
        head = f"# Log — {title}\n"
    else:
        with open(p) as f:
            head = f.read().rstrip("\n") + "\n"
    # heading: "## <time> · <who> · <sub-todo>" (who / sub-todo optional)
    tag = (f" · {by or 'anon'} · {sub}" if sub else f" · {by}" if by else "")
    write(p, head + f"\n## {now()}{tag}\n{message.strip()}\n")


def summary(root, tid, archived=False):
    t = load(root, tid, archived)
    base = os.path.dirname(t["path"])
    subs = [{"i": i, "state": s["state"], "text": s["text"],
             # pictures: as written, and as an absolute path to show them with
             "images": [{"name": im["name"], "path": im["path"],
                         "file": os.path.normpath(os.path.join(base, os.path.expanduser(im["path"])))}
                        for im in s.get("images", [])]}
            for i, s in enumerate(t["subs"])]
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


def unarchive(root, tid):
    src, lsrc = todo_path(root, tid, True), log_path(root, tid, True)
    shutil.move(src, os.path.join(root, "Todos", tid + ".md"))
    if os.path.exists(lsrc):
        shutil.move(lsrc, log_path(root, tid))
    t = load(root, tid)
    t["meta"]["done"] = "false"
    save(t)


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
        return {"folder": root, "groups": groups(root), "groupOrder": group_order(root),
                "supers": supers(root), "superOrder": super_order(root), "todos": todos}
    if cmd == "log-show":
        return {"title": load(root, rest[0], archived)["title"], "entries": log_entries(root, rest[0], archived)}
    if cmd == "log-all":
        # every active todo's log, each entry tagged super group › group › todo (› sub-todo)
        g, out = groups(root), []
        for i in all_ids(root):
            t = load(root, i)
            grp = t["meta"].get("group", "")
            sup = g.get(grp, {}).get("super", "") if grp else ""
            for e in log_entries(root, i):
                e.update({"id": i, "title": t["title"], "group": grp, "super": sup})
                out.append(e)
        return {"entries": out}
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
            unarchive(root, tid)
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
        if cmd == "group-delete":
            # the group goes; its todos (active and archived) just lose it
            name = " ".join(rest).strip()
            n = 0
            for arch in (False, True):
                for i in all_ids(root, arch):
                    t = load(root, i, arch)
                    if t["meta"].get("group", "") == name:
                        t["meta"]["group"] = ""
                        save(t)
                        n += 1
            g = groups(root)
            g.pop(name, None)
            save_groups(root, g, [x for x in group_order(root) if x != name])
            return {"deleted": name, "ungrouped": n}
        # ---- super groups (groups of groups) ----
        if cmd == "super-set":
            # put GROUP into SUPER ("" takes it out); the super is made if new
            grp, sup = rest[0].strip(), " ".join(rest[1:]).strip()
            g, sp = groups(root), supers(root)
            if not grp:
                raise Fail("super-set needs a group")
            g.setdefault(grp, {"color": PALETTE[len(g) % len(PALETTE)]})
            if sup:
                if sup in g:
                    raise Fail(f"'{sup}' is already a group's name")
                sp.setdefault(sup, {"color": PALETTE[(len(sp) + 3) % len(PALETTE)]})
                g[grp]["super"] = sup
            else:
                g[grp].pop("super", None)
            so = super_order(root)
            if sup and sup not in so:
                so = so + [sup]
            save_groups(root, g, sup=sp, sorder=so)
            return {"group": grp, "super": sup}
        if cmd == "super-rename":
            old, new = rest[0].strip(), " ".join(rest[1:]).strip()
            sp = supers(root)
            if old not in sp or not new:
                raise Fail(f"no super group '{old}'" if old not in sp else "super-rename needs a new name")
            if new != old and (new in sp or new in groups(root)):
                raise Fail(f"'{new}' is already taken")
            sp[new] = sp.pop(old)
            g = groups(root)
            for v in g.values():
                if v.get("super") == old:
                    v["super"] = new
            save_groups(root, g, sup=sp, sorder=[new if x == old else x for x in super_order(root)])
            return {"renamed": old, "to": new}
        if cmd == "super-delete":
            # the super goes; its groups stay, just no longer inside it
            name = " ".join(rest).strip()
            sp, g = supers(root), groups(root)
            sp.pop(name, None)
            for v in g.values():
                if v.get("super") == name:
                    v.pop("super", None)
            save_groups(root, g, sup=sp, sorder=[x for x in super_order(root) if x != name])
            return {"deleted": name}
        if cmd == "super-order":
            names = [n for n in rest if n]
            save_groups(root, groups(root), sorder=names + [n for n in super_order(root) if n not in names])
            return {"superOrder": super_order(root)}
        if cmd == "group-rename":
            old, new = rest[0].strip(), " ".join(rest[1:]).strip()
            if not old or not new:
                raise Fail("group-rename needs the old and the new name")
            if new != old and new in groups(root):
                raise Fail(f"there's already a group called '{new}'")
            n = 0
            for arch in (False, True):
                for i in all_ids(root, arch):
                    t = load(root, i, arch)
                    if t["meta"].get("group", "") == old:
                        t["meta"]["group"] = new
                        save(t)
                        n += 1
            g = groups(root)
            g[new] = g.pop(old, {"color": PALETTE[len(g) % len(PALETTE)]})
            save_groups(root, g, [new if x == old else x for x in group_order(root)])
            return {"renamed": old, "to": new, "todos": n}
        if cmd in ("group-archive", "super-archive"):
            # every active todo in the group (or in any group of the super group)
            name = " ".join(rest).strip()
            g, done = groups(root), []
            for i in all_ids(root):
                t = load(root, i)
                grp = t["meta"].get("group", "")
                if (grp == name) if cmd == "group-archive" else (grp and g.get(grp, {}).get("super") == name):
                    shutil.move(t["path"], os.path.join(root, "Archive", i + ".md"))
                    if os.path.exists(log_path(root, i)):
                        shutil.move(log_path(root, i), log_path(root, i, True))
                    done.append(i)
            return {"archived": done}
        if cmd in ("group-restore", "super-restore"):
            # every archived todo in the group (or in any group of the super group)
            name = " ".join(rest).strip()
            g, done = groups(root), []
            for i in all_ids(root, True):
                t = load(root, i, True)
                grp = t["meta"].get("group", "")
                if (grp == name) if cmd == "group-restore" else (grp and g.get(grp, {}).get("super") == name):
                    unarchive(root, i)
                    done.append(i)
            return {"restored": done}
        if cmd == "group-order":
            names = [n for n in rest if n]
            save_groups(root, groups(root), names + [n for n in group_order(root) if n not in names])
            return {"groupOrder": group_order(root)}
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
        elif cmd == "sub-image-add":
            # copy a picture into Attachments/<id>/ and hang it under sub-todo N
            n, src = int(rest[1]), os.path.expanduser(" ".join(rest[2:]).strip())
            if src.startswith("file://"):
                src = urllib.parse.unquote(src[7:])
            if not os.path.isfile(src):
                raise Fail(f"no file '{src}'")
            if not src.lower().endswith(IMAGE_EXT):
                raise Fail("that isn't a picture")
            if not 0 <= n < len(t["subs"]):
                raise Fail(f"no sub-todo {n}")
            adir = os.path.join(root, "Attachments", tid)
            os.makedirs(adir, exist_ok=True)
            stem, ext = os.path.splitext(os.path.basename(src))
            stem = re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-") or "picture"
            name, k = stem + ext.lower(), 2
            while os.path.exists(os.path.join(adir, name)):
                name, k = f"{stem}-{k}{ext.lower()}", k + 1
            shutil.copy2(src, os.path.join(adir, name))
            t["subs"][n].setdefault("images", []).append({"name": stem, "path": f"../Attachments/{tid}/{name}"})
        elif cmd == "sub-image-remove":
            # take picture K off sub-todo N (its file goes to the trash)
            n, k = int(rest[1]), int(rest[2])
            ims = t["subs"][n].get("images", []) if 0 <= n < len(t["subs"]) else []
            if not 0 <= k < len(ims):
                raise Fail("no such picture")
            im = ims.pop(k)
            f = os.path.normpath(os.path.join(os.path.dirname(t["path"]), im["path"]))
            if os.path.isfile(f) and os.path.commonpath([f, os.path.join(root, "Attachments")]) == os.path.join(root, "Attachments"):
                trash = os.path.join(root, ".slime", "trash", dt.datetime.now().strftime("%Y%m%d-%H%M%S-") + tid + "-pictures")
                os.makedirs(trash, exist_ok=True)
                shutil.move(f, trash)
        elif cmd == "delete":
            trash = os.path.join(root, ".slime", "trash", dt.datetime.now().strftime("%Y%m%d-%H%M%S-") + tid)
            os.makedirs(trash, exist_ok=True)
            shutil.move(t["path"], trash)
            if os.path.isdir(os.path.join(root, "Attachments", tid)):
                shutil.move(os.path.join(root, "Attachments", tid), os.path.join(trash, "Attachments"))
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
                append_log(root, tid, f"{verb}: {s['text']}" + (f"\n\n{note}" if note else ""), by, archived, s["text"])
                return summary(root, tid, archived)
        elif cmd == "log-edit":
            edit_log(root, tid, int(rest[1]), " ".join(rest[2:]), opts.get("expect"), archived)
            return {"edited": tid, "n": int(rest[1])}
        elif cmd == "log":
            sub = sub_at(t, opts["sub"])["text"] if opts.get("sub", "") != "" else ""
            append_log(root, tid, " ".join(rest[1:]), by, archived, sub)
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
