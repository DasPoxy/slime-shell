# Slime-Tasks — the command centre's Tasks tab

A todo, task-log and progress suite built into the command centre, in a
tavern the slime has swallowed whole. Three signs hang from the beam:

| Tab | What it's for |
|---|---|
| **Todo** | Top-level todos, grouped and colour-coded. Each opens into its own list of sub-todos, which move *to do → in progress → done*. |
| **Task Log** | What's being worked on: each todo's sub-todos in *to do / in progress / done* lanes, and its log of progress notes and output (newest first). Agents fill this in as they work, and so can you: click a sub-todo to move it a lane on (right-click: back), and write your own log entries. |
| **Progress** | How far along every group and todo is, in collapsible sections. Archive finished lists; search the archive and restore them. |

**Pop-out:** `omarchy-shell slime-shell tasks` (suggested key: **Super+Ctrl+Shift+Return**)
opens the whole suite in a floating panel in the middle of the screen, over
everything. **Esc** closes it.

Everything is keyboard driven — press **?** in the tab for the full list:

- **Tab / 1 2 3** switch tabs · **Esc** backs out (or closes the command centre)
- Todo: **↑↓** pick · **→/Enter** open sub-todos · **n** new · **a** add sub-todo ·
  **Space** finish / cycle a sub-todo · **e** rename/edit · **g** group menu ·
  **A** archive · **d d** delete · **f** show/hide finished ·
  **J/K** or **Shift+↑↓** move the todo / sub-todo
- Task Log: **↑↓** pick · **→/Enter** into the lanes, then **→/Space** move a
  sub-todo on and **←** back · **w** write in the log · **PgUp/PgDn** scroll
- Progress: **↑↓** pick · **Enter/Space** expand · **A** archive · **/** search the archive

Right-click a todo for the same group menu (existing groups, a new one, no
group, rename, archive, delete). Each group gets its own colour. Drag todos
and sub-todos to reorder them; drop a todo in another group (or on its
heading) to move it there.

## Where it's stored

Plain markdown in **`~/Documents/Slime-Notes`**, so Envy, Obsidian or any text
editor can read and edit it too:

```
Slime-Notes/
  Todos/<id>.md        one per todo
  Logs/<id>.md         its task log
  Archive/             archived todos (Archive/Logs/ their logs)
  .slime/groups.json   group colours
  .slime/trash/        deleted todos, just in case
```

A todo file:

```markdown
---
group: Slime Shell
done: false
created: 2026-09-26 13:40
---
# Overhaul the tasks tab

- [ ] a sub-todo
- [/] one being worked on
- [x] one that's finished
```

A log file is a list of `## <date time> · <who>` entries with markdown under
each (code blocks included).

**With Envy (or another notes app):** point it at the folder, or move the
folder inside your vault and tell Slime-Tasks where it went:

```sh
slime-tasks folder ~/Documents/Envy/Slime-Notes
```

The **From your notes** section at the bottom of the Todo tab still lists
every `- [ ]` checkbox in your notes vault (Envy's, `~/Notes`, or a folder you
choose) and ticks them in place, as the old Tasks tab did.

## For agents and scripts

`slime-tasks` (installed to `~/.local/bin` by `slime-shell install`) is the
same backend the tab uses. Every command prints JSON; failures go to stderr
with a non-zero exit.

```sh
slime-tasks find "tasks tab"                    # -> the todo's id
slime-tasks list                                # every todo and sub-todo
slime-tasks add "Overhaul the tasks tab" --group "Slime Shell"
slime-tasks sub-add <id> "Backend CLI"
slime-tasks start <id> <n> "picking this up" --by claude     # -> in progress, logged
slime-tasks log <id> "progress, output, findings…" --by claude
slime-tasks finish <id> <n> "done: 12 tests pass" --by claude  # -> done, logged
slime-tasks sub-set <id> <n> todo|doing|done [--expect TEXT]
slime-tasks order <id> <id> …                   # put todos in this order
slime-tasks archive <id>   /   unarchive <id>
slime-tasks --help                              # everything else
```

`<n>` is a sub-todo's 0-based position. The tab re-reads the folder every two
seconds while it's open, so you can watch an agent shift sub-todos across the
lanes and write its log. Writes are locked and atomic, so the tab and an agent
never clobber each other; `--expect` makes a state change refuse if the
sub-todo's text changed meanwhile.
