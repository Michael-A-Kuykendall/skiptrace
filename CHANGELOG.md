# Changelog

All notable changes to skiptrace are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

First public line. The system version in `skiptrace.asd` is 0.1.0. Nothing is tagged yet.

### Added

- Static scanner for `#+` / `#-` and ASDF `:if-feature`. It does not `READ` the files it audits.
- Reports for contradictions, likely typos, forms the loaded profiles never read, untested features, and `#+nil` / `#+ignore`.
- `--all`, `--json`, `--strict`, `--profiles`, `--profile-dir`, and `--known`.
- `--strict` exits 1 only for contradictions and likely typos. A missing path exits 2.
- Real profiles captured on linux x86-64: SBCL 2.2.9.debian and ECL 21.2.1.
- Handwritten CCL, ABCL, SBCL macOS, and SBCL Windows profiles, kept in `profiles/approximate/` and left out of the default matrix. `--profiles` still finds them by name.
- Command `bin/skiptrace` for SBCL, ECL, CLISP, and CCL.
- ASDF system `skiptrace`. The shell launcher passes `profiles/` next to the checkout. `audit-paths` takes `:profile-dir`.
- `dump-features.lisp` for capturing a profile from the running image.
- `sweep.sh`, which clones 18 libraries and writes a text report for each. `corpus/` and `sweep/` are gitignored.
- Tests run on SBCL, ECL, and CLISP, including a push onto `*features*` inside a comment or a string, which does not count.
- GitHub Actions workflow that installs SBCL, ECL, and CLISP and runs the tests, plus a DCO check on pull requests.
- Project docs: license, conduct, contributing, security, governance, DCO, changelog, roadmap, sponsors.

### Changed

- The system, package, command, and repository name are skiptrace.
- License is MIT.

[Unreleased]: https://github.com/Michael-A-Kuykendall/skiptrace/commits/main
