# Contributing to Sigil

Thanks for taking the time to contribute. Sigil is a small, opinionated
tool — these notes keep changes consistent with how the rest of it is
built.

## What Sigil is (and isn't)

Sigil is a set of SwiftUI overlays and a shell CLI layered on top of
[AeroSpace](https://github.com/nikitabobko/AeroSpace). It manages
*workspace identity* (names, icons, palettes) and *display topology* —
it does not replace your window manager. AeroSpace tiles the windows;
Sigil decorates and drives the workspaces.

It is AeroSpace-only today. There's no yabai support and no plan to add
a multi-window-manager abstraction — that path was tried and removed
because the abstraction cost more than it bought.

## Development setup

```bash
git clone git@github.com:adames/sigil.git
cd sigil

swift build -c release   # build all binaries
./install.sh             # build + symlink into ~/.local/bin
```

Requirements: macOS 14+, Swift 6.0+ (Xcode or Command Line Tools),
AeroSpace.

### Running the tests

```bash
swift test
```

Heads up: tests use [Swift Testing](https://github.com/swiftlang/swift-testing)
(`import Testing`), and **`swift test` requires full Xcode, not just the
Command Line Tools.** CLT can *compile* the test bundle but its
`swiftpm-testing-helper` no-ops on Swift Testing bundles, so the tests
never actually run. `swift build -c release` works fine on CLT. The
framework/linker plumbing for this lives — and is explained — at the top
of [Package.swift](Package.swift).

## Project layout

| Path | What lives there |
|------|------------------|
| `Sources/DisplayTopology` | Display detection + snapshot/caching |
| `Sources/LayoutPolicy` | Density classification → layout decisions |
| `Sources/WorkspaceState` | Workspace config, icons, AeroSpace window manager |
| `Sources/AerospaceEmit` | Renders the sigil-fenced block in `aerospace.toml` |
| `Sources/AdaptersAppKit` | AppKit/accessibility bridge used by `ws-topologyd` |
| `Sources/WsUI` | Shared SwiftUI helpers (kept deliberately tiny) |
| `Sources/ws-*` | The executable targets (one folder per binary) |
| `cli/ws` | The user-facing Bash CLI |
| `lib/` | Shared shell helpers sourced by the CLI |
| `Tests/` | Swift Testing targets |

The binaries and their triggers are documented in the
[README](README.md#binaries).

## Code style

**Swift**
- 4-space indentation, ~100-column lines.
- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Keep `WsUI` small — anything app-specific (palettes, controllers)
  belongs in the executable target, not the shared library.
- Use `WorkspaceConfig` for paths and identifiers; don't hardcode
  personal paths.

**Bash**
- 2-space indentation; quote every expansion (`"$VAR"`); use `[[ ]]`.
- CLI subcommands are `cmd_*` functions; private helpers are `_`-prefixed.
- Source helpers from `lib/` rather than re-implementing them.
- Run `shellcheck cli/ws install.sh` before sending a change.

## Commit messages

```
component: brief summary in the imperative

Longer explanation if the change isn't obvious. Wrap at 72 columns.
```

Examples from the history:
- `refactor: drop unused availableFonts parameter from IconResolver.resolve`
- `docs: stop WorkspaceService/WindowSource comments claiming nonexistent mocks`

## Submitting changes

1. Branch off `main` (`git checkout -b your-change`).
2. Keep commits focused; explain the *why* in the body.
3. Make sure `swift build -c release` is warning-clean and tests pass.
4. Open a PR against `main` using the
   [pull request template](.github/pull_request_template.md).

## Questions and security

- Open an issue for anything you'd like to discuss first.
- For security-sensitive reports, **don't** open a public issue — see
  [SECURITY.md](SECURITY.md).

By contributing you agree your contributions are licensed under the MIT
License (see [LICENSE](LICENSE)).
