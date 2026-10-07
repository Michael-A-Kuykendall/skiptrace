# Developer Certificate of Origin

Every commit on a pull request needs a `Signed-off-by` line. That line is the signer's statement that they can submit the change under the MIT license in [LICENSE](LICENSE).

skiptrace uses DCO 1.1 instead of a separate contributor license agreement. The certificate below is the Linux Foundation text. It may not be edited.

## Certificate

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

## Signing a commit

```bash
git commit -s -m "Describe the change"
```

Git appends `Signed-off-by:` using the name and email on that commit. Sign your own commits. Do not add the line for someone else.

One clone can sign every commit:

```bash
git config format.signoff true
```

Leave that setting local to the clone. A commit that already exists and has not been pushed can be re-signed with `git commit --amend -s`. A range can be re-signed with `git rebase --signoff`, then updated on the remote with `--force-with-lease`.

Questions about a contribution go to [michaelallenkuykendall@gmail.com](mailto:michaelallenkuykendall@gmail.com).

## What the check looks at

[.github/workflows/dco-check.yml](.github/workflows/dco-check.yml) reads non-merge commits in `origin/main..HEAD`. Each one needs a `Signed-off-by:` line. Commits already on `main` are outside that range.
