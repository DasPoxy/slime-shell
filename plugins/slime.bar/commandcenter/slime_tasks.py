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
  sub-edit ID N TEXT [--expect OLD]
  sub-set ID N todo|doing|done [--expect TEXT]
  sub-delete ID N [--expect TEXT]   (its lines go to .slime/trash/deleted-sub-todos.md)
  sub-image-add ID N FILE           copy a picture to Attachments/ID/ and attach it to sub-todo N
  sub-image-remove ID N K [--expect TEXT]  take picture K off sub-todo N (the file goes to the trash)
  sub-move ID N TO [--expect TEXT]  reorder sub-todos
  (--expect: sub-todo N must still read TEXT, else nothing changes)
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
    """Atomic (a temp file, then a rename), keeping the file's permissions:
    a file that's there keeps its own; a new one gets the usual ones (your
    umask), not the temp file's owner-only."""
    d = os.path.dirname(path)
    try:
        mode = os.stat(path).st_mode & 0o7777
    except OSError:
        mask = os.umask(0)
        os.umask(mask)
        mode = 0o666 & ~mask
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, mode)
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
    """A todo file: its front matter, title and sub-todos, plus where each sits
    in the file (so a save can change just those lines; see render)."""
    with open(path) as f:
        lines = f.read().split("\n")
    meta, meta_line, body_start = {}, {}, 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                body_start = i + 1
                break
            k, sep, v = lines[i].partition(":")
            if sep and k.strip():
                meta[k.strip()] = v.strip()
                meta_line[k.strip()] = i
    title, title_line, subs, blanks = "", -1, [], 0
    for i in range(body_start, len(lines)):
        line = lines[i]
        if title_line < 0 and line.startswith("# "):
            title, title_line = line[2:].strip(), i
            continue
        m = SUB.match(line)
        if m:
            subs.append({"line": i, "end": i + 1, "state": MARK_STATE[m.group(2)], "text": m.group(3),
                         "indent": len(m.group(1)), "images": []})
            blanks = 0
            continue
        m = IMG.match(line)
        if m and subs and len(m.group(1)) > subs[-1]["indent"] and i - blanks == subs[-1]["end"]:
            subs[-1]["images"].append({"name": m.group(2), "path": m.group(3)})
            subs[-1]["end"] = i + 1
            blanks = 0
            continue
        # a sub-todo's further lines: indented under it (Markdown list
        # continuation), blank lines between paragraphs kept
        if not line.strip():
            blanks += 1
            continue
        lead = len(line) - len(line.lstrip(" "))
        if subs and lead > subs[-1]["indent"] and i - blanks == subs[-1]["end"]:
            if subs[-1]["images"] or subs[-1].get("extra"):
                # indented under it, after its pictures: kept with it as written
                subs[-1].setdefault("extra", []).extend(lines[subs[-1]["end"]:i + 1])
            else:
                cut = min(lead, subs[-1]["indent"] + 2)
                subs[-1]["text"] += "\n" * (blanks + 1) + line[cut:].rstrip()
            subs[-1]["end"] = i + 1
        blanks = 0
    # what each sub-todo looked like, to tell later whether it changed
    for s in subs:
        s["orig"] = lines[s["line"]:s["end"]]
        s["was"] = sub_lines(s)
    return {"meta": meta, "title": title, "subs": subs, "lines": lines, "metaLine": meta_line,
            "metaOrig": dict(meta), "titleLine": title_line, "titleOrig": title, "bodyStart": body_start}


def sub_lines(s):
    """A sub-todo as markdown lines: the checkbox line, further lines indented
    under it, then its pictures."""
    ind = " " * s.get("indent", 0)
    first, *more = s["text"].strip().split("\n")
    out = [f"{ind}- [{STATE_MARK[s['state']]}] {first}"] + [(ind + "  " + ln).rstrip() for ln in more]
    return (out + [f"{ind}  ![{im['name']}]({im['path']})" for im in s.get("images", [])]
            + s.get("extra", []))


def render(todo):
    """The todo as file text. A todo read from a file is changed in place:
    only the front matter keys, title and sub-todos that changed are
    rewritten, and every other line (notes, other lists, states Slime-Tasks
    doesn't use) stays exactly as it was."""
    meta = todo["meta"]
    if "lines" not in todo:   # a new todo
        out = ["---"] + [f"{k}: {v}" for k, v in meta.items() if v != ""] + ["---", f"# {todo['title']}", ""]
        for s in todo["subs"]:
            out += sub_lines(s)
        return "\n".join(out) + "\n"
    lines = list(todo["lines"])
    repl, head = {}, []   # line index -> replacement lines ([] removes it); lines put first
    # front matter: changed keys in place, gone ones out, new ones at its end
    if meta != todo["metaOrig"]:
        new_keys = []
        for k, v in meta.items():
            at = todo["metaLine"].get(k)
            if at is None:
                if v != "":
                    new_keys.append(f"{k}: {v}")
            elif v != todo["metaOrig"].get(k):
                repl[at] = [f"{k}: {v}"] if v != "" else []
        for k, at in todo["metaLine"].items():
            if k not in meta:
                repl[at] = []
        if new_keys:
            if todo["bodyStart"]:
                close = todo["bodyStart"] - 1
                repl[close] = repl.get(close, []) + new_keys + [lines[close]]
            else:   # no front matter yet
                head = ["---"] + new_keys + ["---"]
    if todo["title"] != todo["titleOrig"]:
        if todo["titleLine"] >= 0:
            repl[todo["titleLine"]] = [f"# {todo['title']}"]
        else:
            at = todo["bodyStart"]
            repl[at] = [f"# {todo['title']}", ""] + ([lines[at]] if at < len(lines) else [])
    # sub-todos: the places the old ones held get the new ones, in order
    # (unchanged ones keep their exact lines); extra new ones follow the last
    olds = sorted((s for s in todo.get("orig_subs", []) if "line" in s), key=lambda s: s["line"])
    blocks = [s["orig"] if s.get("orig") and sub_lines(s) == s.get("was") else sub_lines(s) for s in todo["subs"]]
    if olds:
        for k, o in enumerate(olds):
            mine = blocks[k:k + 1] if k < len(olds) - 1 else blocks[k:]
            repl[o["line"]] = [l for b in mine for l in b]
            for x in range(o["line"] + 1, o["end"]):
                repl[x] = []
    elif blocks:
        # no sub-todos yet: after the title (and the blank line under it)
        at = todo["titleLine"] + 1 if todo["titleLine"] >= 0 else todo["bodyStart"]
        while at < len(lines) and not lines[at].strip() and at in repl:
            at += 1
        new = [l for b in blocks for l in b]
        if at < len(lines) and not lines[at].strip():
            repl[at] = [""] + new + ([""] if at + 1 < len(lines) and lines[at + 1].strip() else [])
        else:
            repl[at] = [""] + new + ([""] + [lines[at]] if at < len(lines) else [])
    out = list(head)
    for i, l in enumerate(lines):
        out += repl[i] if i in repl else [l]
    if len(lines) in repl:
        out += repl[len(lines)]
    text = "\n".join(out)
    return text if text.endswith("\n") else text + "\n"


def check_id(tid):
    """A todo id is a file name in the folder, nothing more: no "/" or "..",
    no hidden name (.slime), so an id can't reach outside the notes folder.
    (Not just the slugs `add` makes: a notes app may name a file "My todo.md".)"""
    if (not tid or tid in (".", "..") or tid.startswith(".") or "/" in tid or "\\" in tid
            or "\0" in tid or os.path.basename(tid) != tid):
        raise Fail(f"'{tid}' isn't a todo id")
    return tid


def todo_path(root, tid, archived=False):
    p = os.path.join(root, "Archive" if archived else "Todos", check_id(tid) + ".md")
    if not os.path.exists(p):
        raise Fail(f"no todo '{tid}'" + (" in the archive" if archived else ""))
    return p


def log_path(root, tid, archived=False):
    return os.path.join(root, "Archive/Logs" if archived else "Logs", check_id(tid) + ".md")


def load(root, tid, archived=False):
    p = todo_path(root, tid, archived)
    t = parse(p)
    t["path"] = p
    t["orig_subs"] = list(t["subs"])   # where the sub-todos were (render)
    return t


def save(t):
    write(t["path"], render(t))


def now():
    return dt.datetime.now().strftime("%Y-%m-%d %H:%M")


def group_file(root):
    """.slime/groups.json: {groups, order, supers, superOrder}."""
    try:
        with open(os.path.join(root, ".slime", "groups.json")) as f:
            g = json.load(f)
        return g if isinstance(g, dict) else {}
    except (OSError, ValueError):
        return {}


def groups(root):
    return group_file(root).get("groups", {})


def group_order(root):
    return group_file(root).get("order", [])


def supers(root):
    """Super groups: {name: {color}} (a group names its super in groups[g]["super"])."""
    return group_file(root).get("supers", {})


def super_order(root):
    return group_file(root).get("superOrder", [])


def save_groups(root, g, order=None, sup=None, sorder=None):
    cur = group_file(root)   # read once: what isn't given stays as it is
    write(os.path.join(root, ".slime", "groups.json"),
          json.dumps({"groups": g, "order": cur.get("order", []) if order is None else order,
                      "supers": cur.get("supers", {}) if sup is None else sup,
                      "superOrder": cur.get("superOrder", []) if sorder is None else sorder}, indent=2) + "\n")


def ensure_group(root, name):
    """A group that's new gets the next colour of the palette."""
    g = groups(root)
    if name and name not in g:
        g[name] = {"color": PALETTE[len(g) % len(PALETTE)]}
        save_groups(root, g)


def archive_todo(root, tid):
    """A todo and its log into the archive."""
    shutil.move(todo_path(root, tid), os.path.join(root, "Archive", tid + ".md"))
    if os.path.exists(log_path(root, tid)):
        shutil.move(log_path(root, tid), log_path(root, tid, True))


def todos_in(root, test, archived=(False, True)):
    """(todo, archived) for every todo whose front matter passes test(meta)."""
    for arch in archived:
        for i in all_ids(root, arch):
            t = load(root, i, arch)
            if test(t["meta"]):
                yield t, arch


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
        e["text"] = log_text(e["text"].strip())
        # older entries: the sub-todo is named in "Started: …" / "Finished: …"
        if not e["sub"]:
            m = re.match(r"^(?:Started|Finished): (.*)", e["text"])
            if m:
                e["sub"] = m.group(1).split("\n")[0].strip()
    return entries


LOG_HEAD = re.compile(r"^## \d{4}-\d\d-\d\d \d\d:\d\d(?: · .*)?$")


def log_body(text):
    """A log entry's text as written to the file: a line that looks like an
    entry's heading (pasted output, say) is escaped (\\## ...), so it can't
    start an entry of its own. Markdown shows it as written."""
    return "\n".join("\\" + l if LOG_HEAD.match(l) else l for l in text.strip().split("\n"))


def log_text(text):
    """The other way: an entry's text as it was given."""
    return "\n".join(l[1:] if l.startswith("\\") and LOG_HEAD.match(l[1:]) else l for l in text.split("\n"))


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
    if expect is not None and log_text("\n".join(lines[start:end]).strip()) != expect.strip():
        raise Fail("that log entry changed meanwhile — reopen it and try again")
    body = log_body(text).split("\n") + [""]
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
    # heading: "## <time> · <who> · <sub-todo>" (who / sub-todo optional);
    # a sub-todo is named by its first line
    sub = sub.split("\n")[0].strip()
    tag = (f" · {by or 'anon'} · {sub}" if sub else f" · {by}" if by else "")
    write(p, head + f"\n## {now()}{tag}\n{log_body(message)}\n")


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
        "order": int(t["meta"].get("order", "0")) if t["meta"].get("order", "").isdigit() else 0,
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


def sub_at(t, n, expect=None):
    """Sub-todo n. With `expect` (its text as the caller last saw it), it must
    still read that: the tab and agents edit at the same time, and a position
    can go stale between a refresh and a keypress."""
    n = int(n)
    if not 0 <= n < len(t["subs"]):
        raise Fail(f"'{t['title']}' has no sub-todo {n}")
    s = t["subs"][n]
    if expect and s["text"] != expect:
        raise Fail(f"sub-todo {n} changed meanwhile (it now reads '{s['text'].split(chr(10))[0]}')")
    return s


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
            if rest[0]:
                write(CONF, json.dumps({"folder": rest[0]}, indent=2) + "\n")
            elif os.path.exists(CONF):
                os.remove(CONF)   # back to the default folder
        ensure(folder())
        return {"folder": folder()}

    root = folder()
    ensure(root)
    archived = bool(opts.get("archived"))

    if cmd == "list":
        # a file that can't be read is left out and named, not the end of the list
        todos, broken = [], []
        for i in all_ids(root, archived):
            try:
                todos.append(summary(root, i, archived))
            except (OSError, ValueError, KeyError, UnicodeDecodeError) as e:
                broken.append({"id": i, "error": f"{type(e).__name__}: {e}"})
        # hand-set order first (0 = never ordered), then oldest first
        todos.sort(key=lambda t: (t["order"] or 10**9, t["created"] or ""))
        return {"folder": root, "groups": groups(root), "groupOrder": group_order(root),
                "supers": supers(root), "superOrder": super_order(root), "todos": todos, "broken": broken}
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
            ensure_group(root, meta["group"])
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
            for t, _ in todos_in(root, lambda m: m.get("group", "") == name):
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
            for t, _ in todos_in(root, lambda m: m.get("group", "") == old):
                t["meta"]["group"] = new
                save(t)
                n += 1
            g = groups(root)
            g[new] = g.pop(old, {"color": PALETTE[len(g) % len(PALETTE)]})
            save_groups(root, g, [new if x == old else x for x in group_order(root)])
            return {"renamed": old, "to": new, "todos": n}
        if cmd in ("group-archive", "super-archive"):
            # every active todo in the group (or in any group of the super group)
            name, g = " ".join(rest).strip(), groups(root)
            inside = (lambda m: m.get("group", "") == name) if cmd == "group-archive" else \
                (lambda m: bool(m.get("group")) and g.get(m.get("group"), {}).get("super") == name)
            done = [os.path.basename(t["path"])[:-3] for t, _ in todos_in(root, inside, (False,))]
            for i in done:
                archive_todo(root, i)
            return {"archived": done}
        if cmd in ("group-restore", "super-restore"):
            # every archived todo in the group (or in any group of the super group)
            name, g = " ".join(rest).strip(), groups(root)
            inside = (lambda m: m.get("group", "") == name) if cmd == "group-restore" else \
                (lambda m: bool(m.get("group")) and g.get(m.get("group"), {}).get("super") == name)
            done = [os.path.basename(t["path"])[:-3] for t, _ in todos_in(root, inside, (True,))]
            for i in done:
                unarchive(root, i)
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
            ims = sub_at(t, n, opts.get("expect")).get("images", [])
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
            archive_todo(root, tid)
            return {"archived": tid}
        elif cmd == "group":
            name = " ".join(rest[1:]).strip()
            t["meta"]["group"] = name
            ensure_group(root, name)
        elif cmd == "sub-add":
            text = " ".join(rest[1:]).strip()
            if not text:
                raise Fail("a sub-todo needs some text")
            t["subs"].append({"state": "todo", "text": text, "indent": 0})
        elif cmd == "sub-edit":
            s = sub_at(t, rest[1], opts.get("expect"))
            s["text"] = " ".join(rest[2:]).strip()
        elif cmd == "sub-delete":
            s = sub_at(t, rest[1], opts.get("expect"))
            t["subs"].remove(s)
            # not gone for good: its lines go to the trash's sub-todo log
            with open(os.path.join(root, ".slime", "trash", "deleted-sub-todos.md"), "a") as f:
                f.write(f"\n## {now()} · {tid}\n" + "\n".join(s.get("orig") or sub_lines(s)) + "\n")
        elif cmd == "sub-move":
            s = sub_at(t, rest[1], opts.get("expect"))
            t["subs"].remove(s)
            t["subs"].insert(max(0, min(len(t["subs"]), int(rest[2]))), s)
        elif cmd in ("sub-set", "start", "finish"):
            s = sub_at(t, rest[1], opts.get("expect"))
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
    except IndexError:
        print("missing arguments (see --help)", file=sys.stderr)
        sys.exit(1)
    except ValueError as e:
        print(f"bad value: {e} (see --help)", file=sys.stderr)
        sys.exit(1)
    if out is not None:
        print(json.dumps(out))


if __name__ == "__main__":
    main()
