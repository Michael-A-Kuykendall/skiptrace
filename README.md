# feature-audit

Finds Common Lisp code that your implementations never read.

`#+sbcl (foo)` isn't just untested on CCL. CCL's reader skips it entirely, so no
test suite or coverage tool can see it. `feature-audit` scans your source without
reading it into Lisp, records every `#+`/`#-` guard and every ASDF `:if-feature`,
and checks each one against real `*features*` lists from the implementations you
care about.

It reports:

- **Contradictions:** code no Common Lisp can ever read, like `#+ccl` nested
  inside `#+sbcl`, or a `#+mcl` branch inside a guard that excludes MCL.
- **Likely typos:** `#+sb_thread` instead of `#+sb-thread`. A misspelled feature
  doesn't error; the code silently disappears.
- **Never read by your matrix:** code for feature combinations you don't test.
- **Untested:** which features you'd need a profile for, ranked by how much code
  depends on them.
- **Risky comment idioms:** `#+nil` and `#+ignore`, which break if anything pushes
  those features. `#+(or)` is the safe form.

## Run it

Zero dependencies. Needs SBCL (other Lisps work too; see `bin/feature-audit.lisp`).

```sh
sbcl --script bin/feature-audit.lisp path/to/your/system/
sbcl --script bin/feature-audit.lisp --all src/            # full read matrix
sbcl --script bin/feature-audit.lisp --strict src/         # exit 1 on contradictions/typos (CI)
sbcl --script bin/feature-audit.lisp --json src/ > audit.json
sbcl --script bin/feature-audit.lisp --profiles sbcl-linux-x86-64,ccl-linux-x86-64 src/
sbcl --script bin/feature-audit.lisp --known my-debug,fiveam-dev src/
```

Try `examples/demo.lisp`, which has one of each problem.

## Profiles

A profile is one implementation's `*features*`, stored in `profiles/*.sexp`.
`sbcl-linux-x86-64` and `ecl-linux-x86-64` were captured from real images.
**The others are approximations written by hand.** Replace them with real ones
from the Lisps you ship on:

```sh
sbcl --script dump-features.lisp > profiles/sbcl-linux-x86-64.sexp
ccl  -b -l dump-features.lisp -e '(quit)' > profiles/ccl-linux-x86-64.sexp
ecl --shell dump-features.lisp > profiles/ecl-linux-x86-64.sexp
```

Capture them with whatever you normally load (ASDF, Quicklisp), since loading those
pushes features too.

## Tests

```sh
sbcl --script tests/run.lisp
```

Or, with ASDF: `(asdf:test-system "feature-audit")`.

## How it works, and its limits

The scanner walks source text the way the reader would: strings, `;` and `#| |#`
comments, character literals like `#\(`, `|escaped symbols|`, quote and backquote
prefixes, and standard `#` dispatch macros. It never calls `READ`, so missing
packages and custom readtables don't stop it.

Known limits:

- **Custom reader macros** (`#?` from cl-interpol, `#_` and `#$` from CCL) are
  assumed to read one following object. That's usually right, and the report notes
  each one it meets.
- **`#.` read-time evaluation** in a guard can't be evaluated statically. Those
  sites are reported as "can't tell", as are nonstandard expressions like Allegro's
  `(version>= 9)`.
- **Features the code pushes itself** (`(pushnew :my-lib *features*)`) are treated
  as unknown, not present, since the push is often conditional. A push inside a
  comment or a string does not count.
- **Stacked guards** like `#+a #+b form` are treated as "both a and b". That matches
  intent; the reader does something odder when `a` holds and `b` doesn't.
- **Contradiction detection** knows that implementations (sbcl, ccl, ecl, ...) and
  OS kernels (linux, darwin, win32, ...) are mutually exclusive. It doesn't know
  every implication between features.

## What it found on its first run

Across 18 popular libraries (about 4,000 guarded forms), with no false positives
after tuning:

- **UIOP** `run-program.lisp`: a `#+mcl` branch inside `%system` that can never
  run, because MCL is missing from both of the function's implementation guards.
- **UIOP** `launch-program.lisp`: `#+lispworks *terminal-io*` nested inside
  `#-(or lispworks abcl)`.
- **SLIME** `swank/ecl.lisp`: `#+(and ecl-weak-hash (or))`, disabled on purpose,
  and the tool says so.

(Checked against the GitHub mirror of ASDF as of its 2023 snapshot; the canonical
repository may differ.)
