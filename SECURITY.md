# Security Policy

## Supported versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

0.1.x is the first release line. Older checkouts of `main` from before the 0.1.0 tag are not a supported line.

## Reporting a vulnerability

Do not open a public GitHub issue for a security vulnerability.

skiptrace is a local source scanner. It reads the paths you give it and writes a report to standard output. It does not evaluate the code it scans. A report about a `#+` in some other project is a normal issue, not a vulnerability in this tool.

### Private disclosure

1. **GitHub Security Advisories (preferred)**
   - Open the [Security tab](https://github.com/Michael-A-Kuykendall/skiptrace/security)
   - Choose "Report a vulnerability"
   - Fill out the advisory

2. **Email**
   - [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com)
   - Put `SECURITY` in the subject
   - For something being exploited right now, put `URGENT SECURITY` in the subject

There is no bug bounty.

### What to include

- What the issue is, and what an attacker could do with it
- Steps to reproduce
- skiptrace version (`skiptrace.asd` `:version`, or the commit)
- Lisp implementation and version
- Operating system
- The smallest source file that triggers it, if the issue is in the scanner
- A suggested fix, if you have one

### Response timeline

- **Initial response:** within 48 hours
- **Triage:** within 7 days, confirm or deny
- **Fix:** within 30 days for a critical issue, 90 days otherwise
- **Disclosure:** after a fix is released and people have had time to update

### Severity

**Critical.** Unexpected code execution while scanning ordinary source. Writing or deleting files the user did not ask to write.

**High.** The scanner follows a path outside the tree the user passed, or leaks the contents of a file the user did not name into the report.

**Medium.** A crash or hang on ordinary source that can be used to stall a CI job. A report that hides a contradiction a caller trusts `--strict` to catch.

**Low.** A local information leak with little impact, or an issue that needs an already-compromised machine.

## Scope

**In scope**

- `src/skiptrace.lisp`, `bin/skiptrace`, and `dump-features.lisp`
- The profile loader, as it decides which files are read
- The GitHub Actions workflows in this repository

**Out of scope**

- Bugs in the code you point skiptrace at
- A `#+` finding you disagree with. That is a normal issue.
- Handwritten profiles under `profiles/approximate/`. They are labeled approximate.
- The third-party checkouts `sweep.sh` clones into `corpus/`. Those stay untracked.
- Vulnerabilities in SBCL, ECL, CLISP, CCL, ABCL, or ASDF themselves

## Legal

Security research that follows this policy will not be met with legal action from this project. Do not access, modify, or delete data that is not yours. Do not test against someone else's deployment without permission.

For anything that is not a vulnerability, use [GitHub issues](https://github.com/Michael-A-Kuykendall/skiptrace/issues).

This policy is effective as of 6 October 2026.
