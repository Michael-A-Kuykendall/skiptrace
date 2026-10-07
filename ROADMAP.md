# Skiptrace roadmap

**Vision:** a small, permanent tool that tells you which Common Lisp forms your implementations never read.

Skiptrace scans source. It does not load the system under audit, and it does not need a library of its own.

## Free forever

**Skiptrace stays free and open source.** That is the project, not a free tier.

- No feature limits
- No usage limits. Use it commercially or personally.
- No paid edition sitting next to a reduced one
- The current version keeps working. There is no forced upgrade.

## Where it is

- The scanner runs on SBCL, ECL, and CLISP, from the shell and from ASDF
- `profiles/` ships captured `*features*` lists for SBCL, ECL, and CLISP on linux x86-64, Clozure CL 1.13 and ABCL 1.9.3 on linux x86-64, SBCL 2.6.9 on Windows x86-64, and SBCL 2.6.8 on Darwin arm64
- `--strict` is for CI. The workflow in this repo runs the three Lisps.
- `sweep.sh` re-checks a fixed 18-library smoke corpus on your machine
- `corpus-scan.py` scans a pinned Quicklisp-format distribution. Tarballs stay in gitignored `corpus/`

## Next

- [ ] Tag 0.1.0
- [ ] Make the GitHub repository public
- [ ] Submit to Quicklisp
- [ ] Further captures, where someone can run the Lisp
- [ ] Keep the SBCL, ECL, and CLISP ports working as those implementations change

A new profile is a capture, with `:source` starting `captured from`. A list that is not part of the default run stays in `profiles/approximate/`.

## Out of scope

- Evaluating `#.` or running the code under audit
- A dependency on Eclector or any other reader library
- Changing `--strict`, the `--json` schema (`profiles`, `sites`, `likely_typos`), or `examples/demo.lisp` so the report looks busier. `--json-full` is an additional report and does not change that schema
- Cloning the 18-library sweep inside CI
