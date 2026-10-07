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

A captured file belongs in `profiles/`, and its `:source` starts with
`captured from`.
