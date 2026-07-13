# Contributing

Thank you for helping improve this KodexBar fork.

## Before Opening a Change

- Confirm that the change belongs in the Plasma widget rather than the CodexBar CLI.
- Preserve the original MIT license and upstream attribution.
- Do not include credentials, account output, local paths, quota values, or machine-specific configuration.
- Keep user-facing text and primary documentation in English.
- Update `README.es.md` when the corresponding English documentation changes.
- Do not replace `contents/ui/main.qml` with an installed local copy.

## Development

Create a topic branch from the current fork branch. Keep changes focused and use imperative commit subjects, for example `Add provider ordering fixture`.

Run validation before opening a pull request:

```sh
scripts/validate.sh
```

The provider behavior tests execute the same JavaScript helper imported by QML. Add or update fixtures when changing ordering, filtering, compact labels, error handling, or Gemini window normalization.

## Pull Requests

Describe the behavior change, affected files, validation performed, and any compatibility impact. Include screenshots only when they contain no account data or personal information. Never replace the original upstream screenshot with a machine-specific capture.

Changes that alter visible quota semantics should explain the chosen behavior and its tradeoffs.
