<div align="center">
  <img src="https://raw.githubusercontent.com/Michael-A-Kuykendall/skiptrace/main/assets/skiptrace-logo.png" alt="skiptrace" width="480" />

  # skiptrace — static analysis for Common Lisp reader conditionals

  Finds Common Lisp code your target implementations never read.

  [![CI](https://github.com/Michael-A-Kuykendall/skiptrace/actions/workflows/ci.yml/badge.svg)](https://github.com/Michael-A-Kuykendall/skiptrace/actions/workflows/ci.yml)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
</div>

## What is skiptrace?

skiptrace audits Common Lisp reader conditionals without loading the code under review. It scans `#+`, `#-`, and ASDF `:if-feature` guards, evaluates them against captured `*features*` profiles, and reports branches that are impossible, suspicious, or never read by the implementations you selected.

`#+sbcl (foo)` is not merely untested on Clozure CL. Clozure's reader skips the form before compilation, so a test suite and ordinary coverage tooling cannot see it. skiptrace works on the source text instead of calling `READ`, which lets it inspect the code that an implementation would otherwise discard.

It currently reports:

- contradictory nested guards that no supported Common Lisp feature set can satisfy;
- likely feature-name typos such as `:sb_thread` vs `:sb-thread`;
- guarded forms that none of the selected implementation profiles read;
- feature names absent from the selected profile matrix;
- risky `#+nil` / `#+ignore` comment idioms;
- `#.` and nonstandard feature syntax that cannot be decided statically.

Zero dependencies. The system and command are both named `skiptrace`.

## Quick start

From the repository root:

```sh
sbcl --script bin/skiptrace examples/
sbcl --script bin/skiptrace --strict examples/
```

The fixture contains one contradiction, one likely typo, one risky `#+nil`, and one safe `#+(or)` disabled-code idiom. The normal run exits `0`; `--strict` exits `1` because the contradiction and typo are CI failures.

Audit your own code:

```sh
sbcl --script bin/skiptrace path/to/your-system/
sbcl --script bin/skiptrace --all src/
sbcl --script bin/skiptrace --strict src/
sbcl --script bin/skiptrace --json src/ > audit.json
sbcl --script bin/skiptrace --profiles sbcl-linux-x86-64,ecl-linux-x86-64 src/
sbcl --script bin/skiptrace --known my-debug,fiveam-dev src/
```

Other launchers:

```sh
ecl --shell bin/skiptrace src/
clisp bin/skiptrace src/
ccl -b -l bin/skiptrace -- src/
```

SBCL, ECL, and CLISP are exercised by the push CI. The launcher also supports CCL, but CCL is not part of the default push workflow.

A leading `--` is ignored, so `sbcl --script bin/skiptrace -- src/` is the same call. CCL requires the separator because that is how it splits its own options from the script's. ECL and CLISP accept the separator and also run without it.

Exit status: `0` clean, `1` with `--strict` when there is a contradiction or likely typo, `2` for invocation errors such as a missing path.

## Install

### From source

Clone the repository and run the launcher in place. `bin/skiptrace` finds `src/` and `profiles/` by walking up from its own file.

To put the command on your `PATH`, symlink the launcher rather than copying it:

```sh
ln -s "$(pwd)/bin/skiptrace" "$HOME/.local/bin/skiptrace"
skiptrace examples/
```

A copied script outside the checkout cannot find `src/` and `profiles/`. The explicit `sbcl`, `ecl`, `clisp`, and `ccl` commands above continue to work from the checkout.

Quicklisp publication is planned for the 0.1.0 release but is not yet an available install path. See [ROADMAP.md](ROADMAP.md).

## From Lisp

```lisp
(asdf:load-asd (truename "skiptrace.asd"))
(asdf:load-system "skiptrace")

(skiptrace:audit-paths '("src/"))
```

With the system loaded and no `:profile-dir`, `audit-paths` uses `asdf:system-relative-pathname` to find `profiles/` next to `skiptrace.asd`. It returns three values: file results, the profiles it loaded, and the analysis plist.

Exported entry points:

- `main`
- `audit-paths`
- `scan-file`
- `parse-feature-expression`
- `eval-feature-expression`
- `load-profiles`

Run the test suite with ASDF:

```lisp
(asdf:test-system "skiptrace")
```

or directly:

```sh
sbcl --script tests/run.lisp
ecl --shell tests/run.lisp
clisp -q -norc tests/run.lisp
```

## Profiles

A profile is a captured `*features*` list from one Lisp image, stored as a plist in `profiles/*.sexp`.

| Profile | Source |
| --- | --- |
| `sbcl-linux-x86-64` | captured from SBCL 2.2.9.debian |
| `ecl-linux-x86-64` | captured from ECL 21.2.1 |
| `clisp-linux-x86-64` | captured from CLISP 2.49.93+ (2018-02-18) |
| `ccl-linux-x86-64` | captured from Clozure CL 1.13 |
| `abcl-linux-x86-64` | captured from ABCL 1.9.3 |
| `sbcl-windows-x86-64` | captured from SBCL 2.6.9 |
| `sbcl-darwin-arm64` | captured from SBCL 2.6.8 |

The default run loads every captured profile in `profiles/`. A handwritten or approximate profile lives under `profiles/approximate/` and is used only when explicitly selected with `--profiles`.

CLISP records this host as `:pc386` and `:word-size=64`; it does not put `:linux` or `:x86-64` on `*features*`.

Capture the features of an image you actually ship:

```sh
sbcl --script dump-features.lisp > profiles/sbcl-linux-x86-64.sexp
ecl --shell dump-features.lisp > profiles/ecl-linux-x86-64.sexp
clisp -q -norc dump-features.lisp > profiles/clisp-linux-x86-64.sexp
ccl -b -l dump-features.lisp -e '(quit)' > profiles/ccl-linux-x86-64.sexp
abcl --noinform --noinit --batch --load dump-features.lisp > profiles/abcl-linux-x86-64.sexp
```

Capture after ASDF or Quicklisp if your application loads them; both may add features. A captured profile's `:source` starts with `captured from`.

`--profiles` selects by the profile's `:name`, not by filename, and every requested name must exist.

## Real-world sweep

`sweep.sh` clones 18 established Common Lisp projects at depth 1 into `./corpus` and writes `./sweep/<name>.txt`. Each report records the exact upstream commit that was scanned. Both directories are gitignored. One library failing does not stop the rest. The sweep runs skiptrace under SBCL.

```sh
sh sweep.sh
```

A snapshot run on 2026-10-06 found three statically unreachable reader-conditional sites and no likely feature-name typos:

- UIOP `uiop/launch-program.lisp:178`: `#+lispworks` inside `#-(or lispworks abcl)` at line 176.
- UIOP `uiop/run-program.lisp:465`: `#+mcl` inside `#+(or abcl clasp clisp cormanlisp ecl gcl genera (and lispworks os-windows) mkcl xcl)` at line 439.
- SLIME `swank/ecl.lisp:1086`: `#+(and ecl-weak-hash (or))`, disabled intentionally. The empty `(or)` is the safe comment idiom.

The first two demonstrate the class of branch skiptrace is designed to expose; the third demonstrates that the scanner can also encounter intentional dead source and report enough context to distinguish it.

Line numbers above are from the upstream revisions checked on 2026-10-06. `sweep.sh` uses the GitHub mirror of ASDF rather than gitlab.common-lisp.net.

Libraries: usocket, bordeaux-threads, cffi, slime, trivial-features, asdf, hunchentoot, ironclad, dissect, dexador, trivial-garbage, iolib, deploy, babel, split-sequence, Postmodern, chipz, woo.

## Limits

The walker handles the standard source structures needed to find reader conditionals: strings, `;` comments, nested `#| |#` comments, character literals, escaped symbols, quote and backquote, and standard `#` dispatch.

- A custom reader macro such as `#?`, CCL's `#_`, or `#$` is assumed to read one following object. The report notes each occurrence.
- Stacked guards such as `#+a #+b form` are modeled as "both a and b" because that matches their apparent intent. The Common Lisp reader has subtler behavior when the first guard succeeds and the second does not.
- Contradiction detection does not encode every possible implication between feature names. It knows that implementation families and OS kernels are mutually exclusive.
- `#.` and malformed/nonstandard feature expressions are reported as statically unknown rather than executed.
- ECL's `DIRECTORY` omits subdirectories from a name/type wildcard, so the walker enumerates directories separately.
- The Lisp sources are ASCII so CLISP can load them without requiring a UTF-8 locale.

## Development and CI

The push workflow installs SBCL, ECL, and CLISP and runs the scanner tests, ASDF tests, launcher checks, a strict self-scan, and the demo exit-code contract.

```sh
sbcl --script tests/run.lisp
ecl --shell tests/run.lisp
clisp -q -norc tests/run.lisp
```

The tests cover feature-expression parsing, escaped symbols, strings and comments, nested and stacked guards, ASDF `:if-feature`, code that mutates `*features*`, typo detection, profile selection, JSON shape, recursive file walking, exit codes, and the known demo findings.

## Community

- Bugs and feature requests: [open an issue](https://github.com/Michael-A-Kuykendall/skiptrace/issues/new/choose).
- Questions: [GitHub Discussions](https://github.com/Michael-A-Kuykendall/skiptrace/discussions).
- Security: [private advisory](https://github.com/Michael-A-Kuykendall/skiptrace/security/advisories/new) or [SECURITY.md](SECURITY.md).
- Contributing, including maintainer-only pull requests and the DCO: [CONTRIBUTING.md](CONTRIBUTING.md).
- Conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Governance: [GOVERNANCE.md](GOVERNANCE.md).
- Roadmap: [ROADMAP.md](ROADMAP.md).
- Changelog: [CHANGELOG.md](CHANGELOG.md).

Pull requests are restricted to approved maintainers. Unsolicited pull requests are declined. Email [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com) to apply for maintainer status.

## Sponsorship

skiptrace stays free to use, copy, modify, and ship, including in commercial work. There is no paid build.

Sponsorship is optional and funds ports, captured profiles, CI maintenance, and ongoing compatibility work. See [SPONSORS.md](SPONSORS.md) or [GitHub Sponsors](https://github.com/sponsors/Michael-A-Kuykendall).

## License

MIT. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
