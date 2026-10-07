# Changelog

All notable changes to Skiptrace are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Static scanner for `#+` / `#-` and ASDF `:if-feature`. It does not `READ` the files it audits.
- Reports for contradictions, likely typos, forms the loaded profiles never read, untested features, and `#+nil` / `#+ignore`.
- `--all`, `--json`, `--strict`, `--profiles`, `--profile-dir`, and `--known`.
- `--strict` exits 1 only for contradictions and likely typos. A missing path exits 2.
- Captured profiles: SBCL 2.2.9.debian, ECL 21.2.1, and CLISP 2.49.93+ (2018-02-18) on linux x86-64; Clozure CL 1.13 and ABCL 1.9.3 on linux x86-64; SBCL 2.6.9 on Windows x86-64; SBCL 2.6.8 on Darwin arm64.
- Command `bin/skiptrace` for SBCL, ECL, CLISP, and CCL.
- ASDF system `skiptrace`. The shell launcher passes `profiles/` next to the checkout. With no `:profile-dir`, `audit-paths` uses `asdf:system-relative-pathname`.
- `dump-features.lisp` for capturing a profile from the running image.
- `sweep.sh`, which clones 18 libraries and writes a text report for each. `corpus/` and `sweep/` are gitignored.
- Tests run on SBCL, ECL, and CLISP, including a push onto `*features*` inside a comment or a string, which does not count.
- GitHub Actions workflow that installs SBCL, ECL, and CLISP and runs the tests, plus a DCO check on pull requests.
- Project docs: license, conduct, contributing, security, governance, DCO, changelog, roadmap, sponsors.
- [EXAMPLES.md](EXAMPLES.md): contradictions and likely typos from 243 libraries. The README lists the best-known ones.
- `--json-full` writes each finding with its file, line, parent guards, and preview, including likely-typo locations, comment idioms, dynamic guards, and scanner notes. `--json` still has only `profiles`, `sites`, and `likely_typos`.
- `corpus-scan.py` scans a pinned Quicklisp-format distribution in one SBCL process and writes a deduplicated summary. `sweep.sh` stays the 18-project smoke corpus.
- Evidence for Quicklisp 2026-01-01 (2,382 projects) and Ultralisp 20261005202000 (2,141 projects) is in `evidence/`. Copied findings share one fingerprint.

### Fixed

- An unclosed `|` or a trailing `\` in a token stops at the end of the file. The scan of that file no longer aborts with a bounds error.
- A directory whose name contains a dot, such as a Quicklisp prefix `bordeaux-threads-v0.9.4`, is scanned. The final component is no longer split into a file name and a type.
- `;` comments and `#| ... |#` comments inside a feature expression are skipped. A comment word is no longer treated as a feature name.
- `--profiles` now rejects a request when any named profile is missing instead of silently using the valid subset.
- Escaped feature symbols now resume normal case folding after `|...|`, preserve escaped colons as symbol data, and handle backslash escapes inside multiple escapes.
- SBCL `--script` again receives the arguments you pass. A path that looks like `bin/skiptrace` is no longer treated as the script name.
- `sweep.sh` invokes `bin/skiptrace`.
- `(asdf:test-system "skiptrace")` signals an error when a check fails, and the profile checks find `profiles/` next to the system rather than next to the compiled file.

### Changed

- The text report headings now say impossible guard chains, forms the selected profiles never read, features absent from those profiles, and other feature names those profiles do not define.
- The README and EXAMPLES state the contradiction and typo rules, how the 243 trees were chosen, and that `sweep.sh` is the 18-project smoke corpus.
- The README now opens with the product and its purpose, distinguishes CI-tested launchers from additional launcher support, moves sponsorship after the technical documentation, and no longer advertises Quicklisp before publication.
- Sweep reports record the exact upstream revision scanned.
- The system, package, command, and repository name are skiptrace.
- License is MIT.

[Unreleased]: https://github.com/Michael-A-Kuykendall/skiptrace/commits/main
