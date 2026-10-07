# Approximate profiles

These were written by hand. They are not loaded unless you name them with
`--profiles`. Replace one by capturing it:

```sh
ccl -b -l dump-features.lisp -e '(quit)' > profiles/ccl-linux-x86-64.sexp
```

Clozure CL 1.13 and Armed Bear Common Lisp 1.9.3 on linux/amd64 have been
captured. Those files are `profiles/ccl-linux-x86-64.sexp` and
`profiles/abcl-linux-x86-64.sexp`. Both dumpers printed the raw name
`linux-x86-64` because the implementation type contains spaces, so the stored
names are `ccl-linux-x86-64` and `abcl-linux-x86-64`. The ABCL command is
`abcl --noinform --noinit --batch --load dump-features.lisp`.

SBCL 2.6.9 on Windows x86-64 has been captured with `sbcl --script
dump-features.lisp`. The dumper's raw name was `sbcl-win32-x86-64`. The
stored name is `sbcl-windows-x86-64`, and the file is
`profiles/sbcl-windows-x86-64.sexp`.

SBCL 2.6.8 on Darwin arm64 has been captured with `sbcl --script
dump-features.lisp`. The dumper's name was already `sbcl-darwin-arm64`.
The file is `profiles/sbcl-darwin-arm64.sexp`.

A captured file belongs in `profiles/`, and its `:source` starts with
`captured from`.
