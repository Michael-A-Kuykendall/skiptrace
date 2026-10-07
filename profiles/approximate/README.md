# Approximate profiles

These were written by hand. They are not loaded unless you name them with
`--profiles`. Replace one by capturing it:

```sh
ccl -b -l dump-features.lisp -e '(quit)' > profiles/ccl-linux-x86-64.sexp
```

Clozure CL 1.13 on linux/amd64 has been captured that way. The file is
`profiles/ccl-linux-x86-64.sexp`. The dumper's raw name was `linux-x86-64`
because Clozure's implementation type contains spaces, so the stored `:name`
is `ccl-linux-x86-64`.

A captured file belongs in `profiles/`, and its `:source` starts with
`captured from`.
