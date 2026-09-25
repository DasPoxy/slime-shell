# Slime Shell

A slime-skinned bar suite for [Omarchy](https://omarchy.org): a shader-drawn
bar of dripping ooze, widgets that float in it, and panels that drip out of it.

## Layout

- `plugins/slime.bar` — the bar. A clone of Omarchy's bar engine with the
  slime skin (shader in `shaders/slime.frag`), floating widget slots, the
  command centre, and the shared slime panel components in `ui/`
  (`SlimeKeyboardPanel`, `SlimePopupCard`, `SlimeMonster`).
- `plugins/slime.*` — widgets cloned from Omarchy's defaults (menu,
  workspaces, agents, indicators, keyboard layout, system update, tray,
  bluetooth, network, audio, monitor, power), restyled for the slime bar.
- `plugins/slime.clock-weather` — clock + weather in one; opens the command
  centre (left click), weather panel (right), date & time settings (middle).
- `layouts/default.json` — the bar layout `slime-shell use` installs.
- `bin/slime-shell` — install the plugins and switch the Omarchy bar to/from
  Slime (backs up and restores your previous bar config).
- `bin/clone-omarchy-plugin` — clone another built-in Omarchy plugin as
  `slime.<name>`.
- `spike/` — the original standalone Quickshell prototype.

## Use

```sh
bin/slime-shell use       # install plugins, back up current bar, switch to Slime
bin/slime-shell restore   # switch back to the previous bar
omarchy-shell slime-shell toggle   # command centre
```

After editing `shaders/slime.frag`, recompile the committed `.qsb`:

```sh
/usr/lib/qt6/bin/qsb --qt6 -o plugins/slime.bar/shaders/slime.frag.qsb plugins/slime.bar/shaders/slime.frag
```

The cloned plugins are derived from Omarchy's shell (MIT).
