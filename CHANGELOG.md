# Changelog

Slime Shell is a suite of Omarchy shell plugins; each release is a git tag
(the plugins' own manifest versions change only when that plugin does).
To go to a release:

```sh
git -C ~/Work/slime-shell checkout v1.0.1 && ~/Work/slime-shell/bin/slime-shell sync
```

## 1.0.1 - 2026-10-09

- **Safety**: every label shows its text as plain text - song and video
  titles from any player or web page, window titles, notification apps, your
  todos - so none of them can render as HTML and make the shell load
  anything from the internet. Slime-Tasks' log entries still render as
  Markdown, but pictures in them become links and raw HTML shows as text.
- **CI**: Slime-Tasks tests, a syntax check of every QML file, the plugin
  manifests and the scripts, on every push.

## 1.0.0 - 2026-10-03

The first release: a slime-themed shell for Omarchy - the bar and its
widgets (workspaces, media with lyrics and cava, clock and weather,
network, Bluetooth, audio, power, tray, system updates, agents...), a
command centre (Tasks, settings, wallpapers, start-up apps, dock), Slime's
notification server, drips, debris and easter eggs. `slime-shell use`,
`restore` (your previous bar, exactly), `sync`, `uninstall`; hands swaps to
Shell-Swapper when it's installed.
