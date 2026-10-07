# skiptrace roadmap

**Vision:** a small, permanent tool that tells you which Common Lisp forms your implementations never read.

skiptrace scans source. It does not load the system under audit, and it does not need a library of its own.

## Free forever

**skiptrace stays free and open source.** That is the project, not a free tier.

- No feature limits
- No usage limits. Use it commercially or personally.
- No paid edition sitting next to a reduced one
- The current version keeps working. There is no forced upgrade.

## Where it is

- Scanner runs on SBCL, ECL, and CLISP, from the shell and from ASDF
- Captured profiles for SBCL and ECL on linux x86-64. CLISP runs the tool. A CLISP profile is not captured yet.
- Handwritten profiles for CCL, ABCL, SBCL on macOS arm64, and SBCL on Windows, available by name and excluded from the default matrix
- `--strict` is suitable for CI. The workflow in this repo runs the three Lisps.
- `sweep.sh` can re-check a fixed list of upstream libraries locally

## Next

- [ ] Tag 0.1.0 and make the GitHub repository public, after the tree is confirmed
- [ ] Submit to Quicklisp
- [ ] Capture a real CLISP profile into `profiles/`
- [ ] Replace each file in `profiles/approximate/` with a capture from a real image
- [ ] Captures beyond linux x86-64: macOS, Windows, and a second architecture where someone can run the Lisp
- [ ] Keep the SBCL, ECL, and CLISP ports working as those implementations change

A new profile is a capture, with `:source` starting `captured from`. A guessed `*features*` list stays in `profiles/approximate/`.

## Out of scope

- Evaluating `#.` or running the code under audit
- A dependency on Eclector or any other reader library
- Changing `--strict`, the JSON schema, or `examples/demo.lisp` so the report looks busier
- Cloning the 18-library sweep inside CI
