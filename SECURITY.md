# Security Policy

## Reporting a vulnerability

Please **don't** open a public issue for security problems.

Email **adameshh@gmail.com** with:

- a description of the issue and its impact,
- steps to reproduce, and
- any relevant logs or proof-of-concept.

You'll get an acknowledgement within a few days. Once a fix is ready,
the details will be disclosed alongside the patch with credit to the
reporter (unless you'd rather stay anonymous).

## Scope

Sigil runs locally and drives AeroSpace and your window layout. The most
relevant surfaces are:

- the `ws` CLI and shell helpers in `lib/` (shell injection, unsafe
  expansion of config values), and
- the daemon `ws-topologyd`, which runs as a LaunchAgent and writes to
  `~/.cache/workspace/`.

There is no network service and no remote attack surface — reports
should focus on local privilege, untrusted config, or unsafe file
handling.

## Supported versions

This is a single-author project; only `main` is supported. Please
reproduce on the latest `main` before reporting.
