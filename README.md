<div align="center">
  <img src="https://raw.githubusercontent.com/Michael-A-Kuykendall/skiptrace/main/assets/skiptrace-logo.png" alt="skiptrace" width="480" />

  Finds Common Lisp forms the reader never reads.
</div>

skiptrace stays free to use, copy, and ship, including in commercial work. There is no paid build. Sponsorship is optional: [GitHub Sponsors](https://github.com/sponsors/Michael-A-Kuykendall), with the amounts listed in [SPONSORS.md](SPONSORS.md).

`#+sbcl (foo)` is not untested on Clozure. Clozure's reader skips the form, so no test suite and no coverage tool can see it. skiptrace scans source without calling `READ`, records every `#+` / `#-` and every ASDF `:if-feature`, and checks each guard against `*features*` lists from the implementations you ship.

Zero dependencies. Not in Quicklisp yet. Clone the repository and run it from the checkout. Version 0.1.0. The system name is `skiptrace`.

## Run it

From the repository root:

```sh
sbcl --script bin/skiptrace path/to/your-system/
sbcl --script bin/skiptrace --all src/
sbcl --script bin/skiptrace --strict src/
sbcl --script bin/skiptrace --json src/ > audit.json
sbcl --script bin/skiptrace --profiles sbcl-linux-x86-64,ecl-linux-x86-64 src/
sbcl --script bin/skiptrace --known my-debug,fiveam-dev src/
```

Other implementations:

```sh
ecl --shell bin/skiptrace src/
clisp bin/skiptrace src/
ccl -b -l bin/skiptrace -- src/
```

A leading `--` is ignored, so `sbcl --script bin/skiptrace -- src/` is the same call. CCL still requires the `--`. That is how CCL splits its own options from the script's. ECL and CLISP accept the separator and also run without it.

## Install

`bin/skiptrace` finds `src/` and `profiles/` by walking up from its own file. Put a symlink to that file on your `PATH`:

```sh
ln -s "$(pwd)/bin/skiptrace" "$HOME/.local/bin/skiptrace"
skiptrace examples/
```

A copy of the script outside the checkout cannot find `src/`. The `sbcl`, `ecl`, and `clisp` commands above keep working. The symlink runs SBCL through the shebang.

Exit status: `0` clean, `1` with `--strict` when there is a contradiction or a likely typo, `2` when the path is missing or no path was given.

Try the fixture first:

```sh
sbcl --script bin/skiptrace examples/
```

That exits 0. The same command with `--strict` exits 1. `examples/demo.lisp` has one contradiction (`#+ccl` inside `#+sbcl`), one typo (`#+sb_thread`), one risky `#+nil`, and one safe `#+(or)` that is not reported.

## From Lisp

```lisp
(asdf:load-asd (truename "skiptrace.asd"))
(asdf:load-system "skiptrace")

(skiptrace:audit-paths '("src/"))
```

With the system loaded and no `:profile-dir`, `audit-paths` uses `asdf:system-relative-pathname` to find `profiles/` next to `skiptrace.asd`. `audit-paths` returns three values: file results, the profiles it loaded, and the analysis plist. The exported entry points are `main`, `audit-paths`, `scan-file`, `parse-feature-expression`, `eval-feature-expression`, and `load-profiles`.

```lisp
(asdf:test-system "skiptrace")
```

or, without ASDF:

```sh
sbcl --script tests/run.lisp
ecl --shell tests/run.lisp
clisp -q -norc tests/run.lisp
```

## What the report means

A guard is a `#+` / `#-` site, or an ASDF `:if-feature` in a `.asd` file. `:if-feature` is not applied to the file that component names. The scanner never calls `READ`, so a missing package or a custom readtable does not stop it.

- **Contradictions.** No Common Lisp can read this form. `#+ccl` nested inside `#+sbcl`, or `#+mcl` inside a guard that lists every implementation except MCL. Implementations and operating-system kernels are treated as mutually exclusive. Other implications are not.
- **Likely typos.** A feature name one edit from a name in your profiles, such as `#+sb_thread` for `:sb-thread`. Version features (`:lispworks4.1`, `:ccl-5.2`) are not treated as typos. A misspelled feature does not error. The form disappears.
- **Never read by your matrix.** Every feature in the guard appears in some profile, but no loaded profile makes the guard true. Often an unsupported-implementation fallback, or a combination you do not test (`clisp` and `win32`).
- **Untested.** The guard needs a feature none of your profiles have. Ranked by how many forms depend on it. This is the list of profiles you still need to capture.
- **`#+nil` / `#+ignore`.** These comment forms out until something pushes `:nil` or `:ignore`. `#+(or)` cannot be made true. `#+(or)` is not reported.
- **Can't tell.** `#.` in a guard, or a nonstandard expression such as Allegro's `(version>= 9)`. A `(push :my-lib *features*)` or `pushnew` makes that feature "maybe", not present, because the push is often itself conditional. The same form in a comment or a string does not count. `(setf *features* (adjoin :x *features*))` is not detected.

`--json` includes contradictions, never-read forms, and likely typos. It omits `#+nil` / `#+ignore`, the untested ranking, and the scanner notes.

`--known feat,feat` adds names to treat as legitimate, so a project feature is not offered as a typo.

## Profiles

A profile is one image's `*features*`, a plist in `profiles/*.sexp`.

| File | Source |
| --- | --- |
| `sbcl-linux-x86-64` | captured, SBCL 2.2.9.debian |
| `ecl-linux-x86-64` | captured, ECL 21.2.1 |
| `clisp-linux-x86-64` | captured, CLISP 2.49.93+ (2018-02-18) |
| `ccl-linux-x86-64` | captured, Clozure CL 1.13 |
| `abcl-linux-x86-64` | captured, ABCL 1.9.3 |
| `sbcl-windows-x86-64` | captured, SBCL 2.6.9 |
| `sbcl-darwin-arm64` | captured, SBCL 2.6.8 |

The default run loads every `*.sexp` directly in `profiles/`. That is the seven captured files. CLISP records this host as `:pc386` and `:word-size=64`. It does not put `:linux` or `:x86-64` on `*features*`. The file name is the machine the list was captured on. Handwritten profiles live in `profiles/approximate/` and stay out of the default matrix. That directory has no profiles left.

```sh
sbcl --script dump-features.lisp > profiles/sbcl-linux-x86-64.sexp
ecl --shell dump-features.lisp > profiles/ecl-linux-x86-64.sexp
clisp -q -norc dump-features.lisp > profiles/clisp-linux-x86-64.sexp
ccl -b -l dump-features.lisp -e '(quit)' > profiles/ccl-linux-x86-64.sexp
abcl --noinform --noinit --batch --load dump-features.lisp > profiles/abcl-linux-x86-64.sexp
```

Capture them in the image you ship, after ASDF or Quicklisp if you load those. Both push features. A captured file's `:source` starts with `captured from`.

`--profiles` selects by the `:name` in the file, not by the filename.

## Sweep

`sweep.sh` clones 18 libraries at depth 1 into `./corpus` and writes `./sweep/<name>.txt`. Both directories are gitignored. One library failing does not stop the rest. It runs SBCL only.

```sh
sh sweep.sh
```

A sweep of those checkouts found three contradictions and no likely typos:

- UIOP `uiop/launch-program.lisp:178`, `#+lispworks` inside `#-(or lispworks abcl)` at line 176.
- UIOP `uiop/run-program.lisp:465`, `#+mcl` inside `#+(or abcl clasp clisp cormanlisp ecl gcl genera (and lispworks os-windows) mkcl xcl)` at line 439.
- SLIME `swank/ecl.lisp:1086`, `#+(and ecl-weak-hash (or))`. Disabled on purpose. The empty `(or)` is the safe comment idiom.

Rechecked 2026-10-06 against `fare/asdf` master and `slime/slime` master. Those line numbers are that checkout. `sweep.sh` clones the GitHub mirror of ASDF, not gitlab.common-lisp.net.

Libraries: usocket, bordeaux-threads, cffi, slime, trivial-features, asdf, hunchentoot, ironclad, dissect, dexador, trivial-garbage, iolib, deploy, babel, split-sequence, Postmodern, chipz, woo.

## Limits

The walker follows the standard reader: strings, `;` comments, nested `#| |#` comments, character literals, `|escaped symbols|`, quote and backquote, and standard `#` dispatch.

- A custom reader macro (`#?`, CCL's `#_` and `#$`) is assumed to read one following object. The report notes each one.
- Stacked guards such as `#+a #+b form` are treated as "both a and b". That matches how they are written. The reader does something else when `a` is true and `b` is not.
- Contradiction detection does not know every implication between features. It knows implementations and OS kernels are mutually exclusive.
- ECL's `DIRECTORY` omits subdirectories from a name/type wildcard. The walker lists directories with a separate wildcard.
- The Lisp sources are ASCII so CLISP can load them without a UTF-8 locale.

## Community

- Bugs and feature requests: [open an issue](https://github.com/Michael-A-Kuykendall/skiptrace/issues/new/choose).
- Questions: [GitHub Discussions](https://github.com/Michael-A-Kuykendall/skiptrace/discussions).
- Security: [private advisory](https://github.com/Michael-A-Kuykendall/skiptrace/security/advisories/new) or [SECURITY.md](SECURITY.md).
- Contributing, including maintainer-only pull requests and the DCO: [CONTRIBUTING.md](CONTRIBUTING.md).
- Conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Who decides: [GOVERNANCE.md](GOVERNANCE.md).
- Where this is going: [ROADMAP.md](ROADMAP.md).
- What changed: [CHANGELOG.md](CHANGELOG.md).

Pull requests are restricted to approved maintainers. Unsolicited pull requests are declined. Email [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com) to apply for maintainer status.

## License

MIT. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
