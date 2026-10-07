# Contributing to skiptrace

Thanks for your interest in skiptrace.

## Maintainer-only pull requests

**Pull requests are restricted to approved maintainers.** Unsolicited pull requests will be declined. To contribute code, apply for maintainer status by emailing [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com).

Anyone can:

- Open an issue for a bug or a feature request
- Join [GitHub Discussions](https://github.com/Michael-A-Kuykendall/skiptrace/discussions)
- Try the tool on a codebase and report what it missed or what it got wrong

## How to contribute

1. Fork the repo and create a branch (`git checkout -b issue-12-short-description`).
2. Make the change with clear commits and tests when the behavior changes.
3. **Sign off your commits** (required): `git commit -s -m "Your message"`.
4. Run the tests on the Lisps you have. The CI set is SBCL, ECL, and CLISP.
5. Open a pull request against `main`.

### Developer Certificate of Origin

Every commit must be signed off with the Developer Certificate of Origin. That certifies you have the right to contribute the code. See [DCO.md](DCO.md).

```bash
git commit -s -m "Your message"
```

To sign off by default in this clone only:

```bash
git config format.signoff true
```

Do not change the global git config of a machine you share unless you mean to.

## What the project is for

Changes should fit the scanner:

- **Zero dependencies.** No Quicklisp libraries, no Eclector, no custom readtable the user has to load.
- **Static.** The scanner does not `READ` the code under audit. Missing packages must not stop a run.
- **Portable.** The same sources run on SBCL, ECL, and CLISP. A fix that works on one of them and breaks another is not done.
- **Stable report.** `--strict` exits 1 only for contradictions and likely typos. The JSON schema stays thinner than the text report: no `#+nil` list, no untested ranking, no scanner notes. `examples/demo.lisp` stays a fixture. Do not edit it so a run looks more interesting.
- **Character literals stay as the reader defines them.** After `#\`, the next character is part of the character name.

## What we welcome

- Bug fixes with a test
- A missed reader case, with the source that triggered it
- A real `*features*` capture, named for the implementation, OS, and machine, with `:source` starting `captured from`
- Documentation that matches what the tool actually prints

## What we decline

- A dependency, including "just for the tests"
- Changing `--strict`, the JSON schema, or the demo to manufacture a finding
- Treating a handwritten profile as a captured one
- Drive-by reformatting of `src/skiptrace.lisp`

## Review

Only approved maintainers may open pull requests. All of those pull requests need approval from the lead maintainer. Review is aimed at a couple of business days. Merge authority stays with the lead maintainer.

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

A `--strict` scan of the tool itself must exit 0. The demo must exit 1:

```bash
sbcl --script bin/skiptrace -- --strict src/ tests/ skiptrace.asd dump-features.lisp
sbcl --script bin/skiptrace -- --strict examples/
```

## Maintainers

- **Lead maintainer:** Michael A. Kuykendall (@Michael-A-Kuykendall)
- **Additional maintainers:** none. This is a solo project until the volume needs another person.

To apply, email [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com) with your GitHub username, the area you want to take (scanner, profiles, portability, docs), how much time you have, and why.

## Recognition

Merged work is recorded in [CHANGELOG.md](CHANGELOG.md) and [AUTHORS.md](AUTHORS.md).

## Questions

Open a [discussion](https://github.com/Michael-A-Kuykendall/skiptrace/discussions) or email [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com).
