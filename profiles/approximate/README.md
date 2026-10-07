# Approximate profiles

These were written by hand. They are not loaded unless you name them with
`--profiles`. Replace one by capturing it:

```sh
ccl -b -l dump-features.lisp -e '(quit)' > profiles/ccl-linux-x86-64.sexp
```

A captured file belongs in `profiles/`, and its `:source` starts with
`captured from`.
