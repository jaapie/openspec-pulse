# openspec-pulse

Tells you which OpenSpec changes have gone quiet, across every repo on this machine, so a change doesn't get forgotten altogether.

Two parts live in this repo:

- a Ruby CLI, `openspec-pulse`, which does all the work and prints a table or JSON
- an Omarchy shell plugin (bar badge and drop-down panel) that displays the CLI's JSON

## Install

You need Ruby 4.0 (the repo pins it in `mise.toml`), Bundler, `git` and the `openspec` CLI on your PATH.

```sh
git clone https://github.com/jaapie/openspec-pulse.git ~/dev/openspec-pulse
cd ~/dev/openspec-pulse
bundle install
bin/openspec-pulse version
```

`bin/openspec-pulse` finds its own `Gemfile`, so it works from any directory. It isn't published as a gem; the gemspec is there so another Ruby app can use it with `gem "openspec-pulse", git: "https://github.com/jaapie/openspec-pulse.git"`.

If `/usr/bin` comes before mise on your PATH (Arch's `ruby` package installs Ruby 3.4 there), the system Ruby runs it instead and fails with `Bundler::GemNotFound`. Put mise's shims first:

```sh
PATH="$HOME/.local/share/mise/shims:$PATH" bin/openspec-pulse status
```

## Config

The config file is `$XDG_CONFIG_HOME/openspec-pulse/config.yml`, which is `~/.config/openspec-pulse/config.yml` when `XDG_CONFIG_HOME` isn't set. There is no default: without the file the CLI stops with an error naming the path it looked for.

```yaml
# Every directory up to 5 levels below these that has openspec/changes/ is a repo.
# node_modules, .git and vendor are skipped.
scan:
  - ~/code
  - ~/dev

# Repos outside the scan roots (optional). Each is named by its folder name.
repos:
  - ~/elsewhere/tool

# An in-progress change with no commits to its folder for this many days is stale.
stale_after_days: 14
```

A repo found twice (by two scan roots, or by a scan root and `repos`) is listed once. A scan root or repo that doesn't exist is shown as an error, not skipped.

## `status`

```sh
bin/openspec-pulse status
bin/openspec-pulse status --json
```

`status` prints one row per active change: repo, change, tasks done, days since its folder was last touched, and a note (`stale`, `in progress`, `not started`, `ready to archive`, a read error, or OpenSpec's own counts when they differ from the parsed ones). Rows are ordered stale first (quietest at the top), then complete (ready to archive), then other changes in progress, then not started. Repos that couldn't be read are listed at the end.

`--json` prints the same report as one JSON document for the Omarchy plugin, including each change's task groups and tasks.

How it decides:

- **Last touched** is the time of the latest commit touching `openspec/changes/<name>/`, or now if that folder has uncommitted edits. A folder that has never been committed, or a repo that isn't a git repo, uses the newest file modification time instead.
- **Kind**: `not_started` when no task is ticked (including no tasks at all), `complete` when every task is ticked, otherwise `in_progress`.
- **Stale**: only `in_progress` changes can be stale, so proposals you haven't started never nag.
- **Read-only and careful with other people's repos**: it only runs `openspec list --json` and read-only git commands (`log`, `rev-parse`, `diff-index --cached`, `ls-files`), never `git status`, and it never writes to a repo. A repo's own `.git/config` can name programs for git to run (an fsmonitor, a `gpg.program`, a clean filter); openspec-pulse switches those off or avoids the commands that use them, and spots uncommitted edits by comparing file sizes and times with what git recorded, without git reading the files.

The exit status is 0 whenever a report was produced, even if some repos had errors, and non-zero only when there is no report at all (for example, a missing config).

## `notify`

```sh
bin/openspec-pulse notify
bin/openspec-pulse notify --force
```

`notify` builds the same report as `status` and, when at least one change is stale or ready to archive, sends one desktop notification stating the counts:

```
You have 6 stale OpenSpec changes, and 2 changes ready to archive.
```

A part with nothing in it is left out ("You have 1 stale OpenSpec change." or "You have 2 OpenSpec changes ready to archive."), and nothing is sent when both are zero. The notification doesn't list changes; the details are in the Omarchy plugin's panel and in `status`.

The notification goes through `omarchy notification send`, so `notify` needs Omarchy. It carries a placeholder "OSP" icon and goes away on its own after a few seconds. Clicking it, or its **See more** button, opens the Omarchy plugin's panel, or a floating terminal showing the `status` table when the plugin isn't installed.

It sends at most once per local calendar day, so it's safe to run often (the Omarchy plugin runs it every 5 minutes). The date of the last digest is kept in `$XDG_STATE_HOME/openspec-pulse/last_digest` (`~/.local/state/openspec-pulse/` by default), so a restart doesn't send a second one.

`--force` sends now, even if today's digest has gone or nudges are off. It doesn't record the date, so the normal daily digest still goes out.

If `omarchy notification send` is missing or fails, `notify` exits non-zero with the reason and doesn't record the date, so the next run tries again.

## `nudges`

```sh
bin/openspec-pulse nudges        # prints on or off
bin/openspec-pulse nudges off
bin/openspec-pulse nudges on
```

Turns the daily digest on or off. Nudges are on until you turn them off. The setting is kept in `$XDG_STATE_HOME/openspec-pulse/nudges` and shows in `status --json` as `nudges`. It only affects the notification: `status` and the bar badge still show stale changes.

## Omarchy plugin

The repo is also an Omarchy shell plugin: `manifest.json`, `Service.qml`, `BarWidget.qml` and the panel's QML sit at its root. It adds a badge to the bar and a drop-down panel, and it gets everything from the CLI, so set up the [config](#config) first.

### Install

```sh
omarchy plugin add https://github.com/jaapie/openspec-pulse.git --enable
cd ~/.config/omarchy/plugins/io.github.jaapie.openspec-pulse
bundle install
```

A local clone works as the URL too (`omarchy plugin add ~/dev/openspec-pulse --enable`); `omarchy plugin update io.github.jaapie.openspec-pulse` pulls later commits. If the badge doesn't appear, restart the shell with `omarchy restart shell`. Do the same after an update that changes the panel: the update reloads the plugin, but the shell keeps its cached copy of the panel's QML until it restarts. To uninstall, run `omarchy plugin remove io.github.jaapie.openspec-pulse`. The plugin's id is `io.github.jaapie.openspec-pulse`; the CLI is still called `openspec-pulse`.

### What it shows

- **Badge**: a task-list glyph, with the number of stale changes beside it in the theme's attention colour, or a warning glyph when the CLI or a repo has an error. Hover for a summary.
- **Panel** (click the badge): totals, then changes grouped as stale, ready to archive, in progress and not yet started. The panel stays one size and pages rather than scrolls. A switch in its header turns the daily reminder on or off, which only affects the notification, not the badge.
- **Change view** (click a change): its task groups in file order, open tasks listed and done ones folded away, plus buttons to open your default agent in the repo (with `/opsx:apply <change>`, told to check with you before changing anything) or open `tasks.md` in your editor. Hover cut-off text to read all of it.

The plugin runs `status --json` every 5 minutes and whenever the panel opens, and `notify` on the same timer; the CLI decides whether a digest is due. The digest's **See more** opens this panel on the focused monitor.

### PATH and Ruby

The shell doesn't start with mise's PATH, so the plugin runs the CLI with its own:

```
~/.local/share/mise/shims : ~/.local/bin : /usr/share/omarchy/bin : /usr/bin : /bin
```

mise's shims come first so Ruby 4.0 and `openspec` are found ahead of Arch's Ruby 3.4 in `/usr/bin`; `/usr/share/omarchy/bin` is where the notification command lives. The plugin uses `openspec-pulse` if it's on that PATH, and otherwise the copy in its own `bin/`, which is why the plugin folder needs `bundle install`.

If the CLI can't be found or fails, the badge shows its warning glyph and the panel shows the error. It never shows an empty list instead.

### The `command` setting

Without mise, or to use a CLI installed somewhere else, set the widget's `command` setting to the full path of the `openspec-pulse` executable, in the bar widget's settings or in `~/.config/omarchy/shell.json`:

```json
{ "id": "io.github.jaapie.openspec-pulse", "command": "/home/you/bin/openspec-pulse" }
```

The plugin still runs it with the PATH above, so the Ruby it starts with must have the gems installed.

## Development

```sh
bundle exec rspec
```
