# Profiles that are not in the default run

A file in this directory loads only when `--profiles` names it. A capture that belongs in the default run goes in `profiles/`, and its `:source` starts with `captured from`.

Dump the running image:

```sh
sbcl --script dump-features.lisp
ecl --shell dump-features.lisp
clisp -q -norc dump-features.lisp
ccl -b -l dump-features.lisp -e '(quit)'
abcl --noinform --noinit --batch --load dump-features.lisp
```

`:name` is the implementation, the operating system, and the machine. When the dumper's raw name contains a space, set `:name` in the file you write. Leave `:features` as the image printed them.
