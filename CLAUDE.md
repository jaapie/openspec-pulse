# openspec-pulse

Shows which OpenSpec changes have gone quiet, across every repo on the user's machine. See README.md for what it does and how to install it.

Two parts, one repo:

- **Ruby CLI** (`bin/openspec-pulse`, `lib/`): all the logic. Thor for argument parsing, stdlib otherwise.
- **Omarchy shell plugin** (`manifest.json` and the QML files at the root): only displays the CLI's JSON.

When working here:

- Build the CLI test-first with RSpec (red, green, refactor), and keep `bundle exec rspec` green.
- Keep judgement in Ruby: the QML lays out what the CLI reports and decides nothing.
- Text from the CLI's JSON is plain text in QML (`textFormat: Text.PlainText`); plugin strings live in `i18n/en.json`.
- The CLI is read-only towards the repos it reads, and must not run any program a repo's own git config names. Never present an error as "nothing to report".
- Check plugin changes with `omarchy plugin validate .`, then in the real shell (`omarchy restart shell` after `omarchy plugin update`).
- The plans live in a private OpenSpec store (`openspec/config.yaml`); without it, OpenSpec commands report an unknown store, which is expected.
