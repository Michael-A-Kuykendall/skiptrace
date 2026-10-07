# Developer Certificate of Origin (DCO)

## Overview

skiptrace uses the Developer Certificate of Origin (DCO) so contributions are licensed and contributors have the right to submit them.

## What is DCO?

The DCO is a lightweight way for contributors to certify that they wrote or otherwise have the right to submit their contribution. It is the industry-standard alternative to a Contributor License Agreement, used by projects such as the Linux kernel, Docker, and GitLab.

## DCO text

By making a contribution to this project, you certify that:

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

## How to sign your commits

Add `-s` when you commit:

```bash
git commit -s -m "Add new feature"
```

That appends:

```
Signed-off-by: Your Name <your.email@example.com>
```

The name and email come from `user.name` and `user.email` in the repository or your environment. Set those for the commit. Do not rewrite someone else's git identity to make a sign-off.

To sign off every commit in one clone:

```bash
git config format.signoff true
```

To add a sign-off to the latest commit you have not pushed:

```bash
git commit --amend --signoff
```

For several unpushed commits, `git rebase --signoff` over that range, then push with `--force-with-lease` if the branch was already on the remote.

## Check

Pull requests are checked by [.github/workflows/dco-check.yml](.github/workflows/dco-check.yml). The check looks at non-merge commits in `origin/main..HEAD`. Each one needs a `Signed-off-by:` line. The root commit already on `main` is outside that range.

If the check fails, add the sign-off and push the branch again with `--force-with-lease`.

## Work from a company

Use the email your employer expects on the commit, and make sure your employment terms allow the contribution. Each person signs off their own commits. You cannot sign off for someone else.

For a large or ongoing corporate contribution, email [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com) before starting.

## Questions

- General questions: a GitHub discussion
- Licensing of a contribution: [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com)
