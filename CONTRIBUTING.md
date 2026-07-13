# Contributing

Thank you for improving ai-cli-control.

## Before submitting a change

1. Keep source code, comments, metadata, and primary documentation in English.
2. Update `README.es.md` and runtime translations when user-visible English text changes.
3. Do not add credentials, personal paths, provider account data, generated caches, or internal workflow notes.
4. Preserve provider commands as argument arrays. Do not add `eval`, `shell=True`, `os.system`, or shell command construction.
5. Keep tests isolated from real provider CLIs and real updates.

## Validation

Run the full local check before proposing a change:

```bash
make check
```

Describe the user-visible behavior, affected files, and validation in a pull request. Do not claim provider support that was not verified by the relevant CLI.
