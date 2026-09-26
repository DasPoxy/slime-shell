# Tasks tab — using your own notes

The command centre's **Tasks** tab lists every checkbox in a folder of markdown
notes and lets you tick them off. It works with [Envy](https://github.com/skuthus/Envy-Universal)
but doesn't need it.

## Which folder it reads

In order, the first that applies:

1. **A folder you set** — Tasks tab → *change*, type a path, *use folder*.
   Stored in `~/.config/omarchy/slime-shell/tasks.json`:
   ```json
   { "folder": "~/Documents/Notes", "subfolders": true }
   ```
   Clear the path (or delete the file) to go back to automatic.
2. **Envy's vault**, from `~/.config/envy/config.md` (`vault = "..."`,
   `include_subfolders = true|false`).
3. **`~/Notes`** or **`~/Documents/Notes`**, if either exists (subfolders
   included).

## What counts as a task

Any line in a `.md` file that looks like a markdown checkbox:

```markdown
- [ ] something to do
- [x] something done
* [ ] stars and pluses work too
```

Hidden folders (starting with `.`) are skipped. Notes are grouped by file,
most recently edited first.

## Ticking tasks

Clicking a task flips just that one line (`[ ]` ↔ `[x]`) with an atomic write.
If the line changed on disk since the list was read (say you edited the note
meanwhile), nothing is written and the tab shows why.

## For agents / scripts

`plugins/slime.bar/commandcenter/tasks.py` is the whole backend:

```sh
tasks.py list                          # {"folder", "source", "tasks": [...]}
tasks.py toggle FILE LINE EXPECTED     # flip line LINE if it still reads EXPECTED
tasks.py set-folder PATH [false]       # use PATH (false = no subfolders); "" = automatic
```

Each task in `list` has `file`, `note`, `line` (0-based), `raw` (the exact
line, used as EXPECTED), `text`, `done` and `mtime`. `source` is `custom`,
`envy`, `default` or `none`. It only ever edits files inside the chosen folder.
