## Description
What changed, and why.

**Branch name**: `issue-{number}-{short-description}`

**Related issue**: Fixes #

## Type of change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation
- [ ] Refactor

## Project constraints
- [ ] No new dependencies
- [ ] The scanner still does not `READ` the code under audit
- [ ] SBCL, ECL, and CLISP still run the tests
- [ ] `--strict` still exits 1 only for contradictions and likely typos
- [ ] The JSON schema is unchanged
- [ ] `examples/demo.lisp` was not edited to manufacture a finding

## Testing
- [ ] `sbcl --script tests/run.lisp`
- [ ] `ecl --shell tests/run.lisp`
- [ ] `clisp -q -norc tests/run.lisp`
- [ ] `sbcl --script bin/skiptrace --strict src/ tests/ bin/skiptrace skiptrace.asd dump-features.lisp` exits 0
- [ ] `sbcl --script bin/skiptrace --strict examples/` exits 1

## Legal
- [ ] Every commit is signed off (`git commit -s`). See [DCO.md](../DCO.md).
- [ ] I have the right to contribute this under the MIT License
- [ ] Third-party code is attributed and already under a compatible license

## Notes
Anything a reviewer should know. A new profile needs a `:source` line that starts with `captured from`, and it belongs in `profiles/`.
