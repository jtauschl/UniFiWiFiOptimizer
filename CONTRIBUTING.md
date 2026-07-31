# Contributing

Bug reports and feature requests are welcome via [GitHub Issues](https://github.com/jtauschl/unifiwifioptimizer/issues) — use the bug/feature templates, they ask for the details (UniFi Network Application version, AP model/firmware) needed to reproduce or evaluate most requests.

## Pull requests

1. Fork the repo and branch off `main`.
2. Keep changes focused — one logical change per PR.
3. Run `shellcheck unifiwifioptimizer scripts/*.sh` and confirm it passes.
4. Test against a real UniFi controller where the change touches API calls, SSH scanning, or the RF corridor math — this project has no automated test suite yet, so manual verification is the only check that exists.
5. Update `docs/PROFILES.md`/`docs/ALGORITHM.md` if the change affects profile fields or the RF model.
6. Open the PR using the provided template — fill in Summary, Risk, and Release notes.

## Code style

- POSIX-compatible Bash where possible, shellcheck-clean.
- `UPPER_CASE` for constants, `lower_case` for local variables.
- Embedded Ruby/Python is for YAML parsing and JSON extraction only — no logic there.
- No external package dependencies — only standard system tools (`bash`, `curl`, `python3`, `ruby`, `ssh`, `awk`).
- The tool never writes to the UniFi controller — read-only stays read-only.

## What won't be merged

- Anything that adds write access to the UniFi controller.
- New external dependencies beyond the standard system tools listed above.
