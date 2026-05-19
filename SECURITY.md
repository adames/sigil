# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.x     | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in Sigil, please report it responsibly:

1. **Do not** open a public issue
2. Email the maintainer directly at: adameshodelin@gmail.com
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

You can expect:
- Acknowledgment within 48 hours
- Assessment within 1 week
- Fix timeline communication
- Credit in the release notes (unless you prefer anonymity)

## Security Considerations

Sigil operates with the following security model:

- **No network access**: Sigil does not make any network connections
- **Local-only**: All data stays on your machine (`~/.config/workspace/`, `~/.cache/workspace/`)
- **Accessibility API**: Uses macOS Accessibility API for window management (requires user permission)
- **LaunchAgents**: Runs as user process, not system daemon

## Audit

The codebase is small and auditable:
- ~3000 lines of Swift
- ~500 lines of Bash
- No external dependencies beyond Swift standard library and Apple frameworks
