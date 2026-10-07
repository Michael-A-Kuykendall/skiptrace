# Contributing to Skiptrace

## Maintainer-only pull requests

Pull requests are restricted to approved maintainers. An unsolicited pull request is declined.

To change code, apply for maintainer status first. Email [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com) with your GitHub username, the area you want to take, and how much time you have.

People who are not maintainers can:

- Open an issue for a bug or a feature request
- Join [GitHub Discussions](https://github.com/Michael-A-Kuykendall/skiptrace/discussions)
- Run the tool and report what it missed or what it got wrong

## How to contribute

Once you are an approved maintainer:

1. Fork the repo and create a branch (`git checkout -b issue-12-short-description`).
2. Make the change with clear commits and tests when the behavior changes.
3. Sign off your commits: `git commit -s -m "Your message"`.
4. Run the tests on the Lisps you have. The CI set is SBCL, ECL, and CLISP.
5. Open a pull request against `main`.

### Developer Certificate of Origin

Every commit must be signed off with the Developer Certificate of Origin. See [DCO.md](DCO.md).

```bash
git commit -s -m "Your message"
```

To sign off by default in this clone only:

```bash
git config format.signoff true
```

## Rules

- **Zero dependencies.** No Quicklisp library, and no Eclector.
- **The scanner does not READ the code under audit.** A missing package must not stop a run.
- **The same sources run on SBCL, ECL, and CLISP.** A fix that works on one of them and breaks another is not done.
- **The report stays stable.** `--strict` exits 1 only for contradictions and likely typos. The JSON keys stay `profiles`, `sites`, and `likely_typos`. `examples/demo.lisp` is a fixture. Do not edit it to manufacture a finding.
- **Character literals stay as the reader defines them.** After `#\`, the next character is part of the character name.
- **A profile in the default run has `:source` starting with `captured from`.**

## What we welcome

- A bug fix with a test
- A missed reader case, with the source that triggered it
- A real `*features*` capture, named for the implementation, the operating system, and the machine
- Documentation that matches what the tool prints

## What we decline

- A dependency, including one that is only for the tests
- A change to `--strict`, the JSON keys, or the demo that manufactures a finding
- A guessed `*features*` list presented as a capture
- Drive-by reformatting of `src/skiptrace.lisp`

## Review

Only approved maintainers open pull requests. Those pull requests need approval from the lead maintainer. Review is aimed at a couple of business days. Merge authority stays with the lead maintainer.

## Development setup

```bash
git clone https://github.com/Michael-A-Kuykendall/skiptrace
cd skiptrace

sbcl --script tests/run.lisp
ecl --shell tests/run.lisp
clisp -q -norc tests/run.lisp
```

With ASDF already loaded in the image:

```lisp
(asdf:load-asd (truename "skiptrace.asd"))
(asdf:test-system "skiptrace")
```

A `--strict` scan of the tool itself exits 0. The demo exits 1 under `--strict`:

```bash
sbcl --script bin/skiptrace --strict src/ tests/ bin/skiptrace skiptrace.asd dump-features.lisp
sbcl --script bin/skiptrace --strict examples/
```

## Maintainers

- **Lead maintainer:** Michael A. Kuykendall (@Michael-A-Kuykendall)
- **Additional maintainers:** none

To apply, email [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com) with your GitHub username, the area you want to take, and how much time you have.

## Recognition

Merged work is recorded in [CHANGELOG.md](CHANGELOG.md) and [AUTHORS.md](AUTHORS.md).

## Questions

Open a [discussion](https://github.com/Michael-A-Kuykendall/skiptrace/discussions) or email [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com).
