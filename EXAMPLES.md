# Examples

Skiptrace reads `#+`, `#-`, and ASDF `:if-feature` without loading the library.

A contradiction is a guarded form whose enclosing reader conditions cannot all be true on one implementation. Operating-system kernels are mutually exclusive the same way: `#+linux` inside `#+darwin` is a contradiction. A likely typo matches a known feature after treating `-`, `_`, and `.` as the same, or is one edit away, and is not a prefix, a suffix, or a digit change.

## Hand-picked git corpus, 2026-10-07

243 public Common Lisp source trees: widely used Quicklisp projects whose recorded source was a git URL, plus the SBCL, Clozure CL, and CLISP repositories. This was not the Quicklisp distribution, not a download ranking, and not a random sample. Each finding below is pinned to the revision scanned. The scan covered 10,114 files and 33,862 guarded forms. Eleven trees produced a contradiction or a likely typo.

cl-base64, CLSQL, and contextl were not cloned. ECL and Maxima were not cloned. Closer to MOP came from GitLab after its GitHub path 404ed.

The 243-source-tree corpus is this page. `sweep.sh` is the smaller 18-project smoke corpus and does not reproduce these results.

The README lists the best-known cases. The sections below say why each one matters.

## UIOP, shipped with ASDF

[fare/asdf](https://github.com/fare/asdf) `f2ded94075a2e6e0b65e66870cf338d1951683e0`

- [`uiop/launch-program.lisp:178`](https://github.com/fare/asdf/blob/f2ded94075a2e6e0b65e66870cf338d1951683e0/uiop/launch-program.lisp#L178) `#+lispworks` is inside [`#-(or lispworks abcl)`](https://github.com/fare/asdf/blob/f2ded94075a2e6e0b65e66870cf338d1951683e0/uiop/launch-program.lisp#L176). The LispWorks stream binding cannot be read.
- [`uiop/run-program.lisp:465`](https://github.com/fare/asdf/blob/f2ded94075a2e6e0b65e66870cf338d1951683e0/uiop/run-program.lisp#L465) `#+mcl` is inside [`#+(or abcl clasp clisp cormanlisp ecl gcl genera (and lispworks os-windows) mkcl xcl)`](https://github.com/fare/asdf/blob/f2ded94075a2e6e0b65e66870cf338d1951683e0/uiop/run-program.lisp#L439). That `or` does not name MCL, so the `ccl::with-cstrs` call cannot be read.

The same MCL form is copied into other trees:

- [SBCL `contrib/asdf/uiop.lisp:6754`](https://github.com/sbcl/sbcl/blob/5ebd83dd58480aaf46e582f5e787705f491ef5ef/contrib/asdf/uiop.lisp#L6754)
- [Clozure CL `tools/asdf.lisp:7219`](https://github.com/Clozure/ccl/blob/ba7111836b41cd4e5df8b7682f8f78eee98c07e9/tools/asdf.lisp#L7219), and the launch-program form at [`tools/asdf.lisp:6204`](https://github.com/Clozure/ccl/blob/ba7111836b41cd4e5df8b7682f8f78eee98c07e9/tools/asdf.lisp#L6204)
- [CLISP `modules/asdf/asdf.lisp:7219`](https://gitlab.com/gnu-clisp/clisp/-/blob/325f8a7000da86d6d991ceb4e81115c8968209fc/modules/asdf/asdf.lisp#L7219), and the launch-program form at [`modules/asdf/asdf.lisp:6204`](https://gitlab.com/gnu-clisp/clisp/-/blob/325f8a7000da86d6d991ceb4e81115c8968209fc/modules/asdf/asdf.lisp#L6204)
- [Quicklisp client `asdf.lisp:6763`](https://github.com/quicklisp/quicklisp-client/blob/6d96fd86c114345bd74d995bb296fae46f1f26ec/asdf.lisp#L6763)
- [lisp-binary `asdf.lisp:6802`](https://github.com/heegaiximephoomeeghahyaiseekh/lisp-binary/blob/ba3220b8b32267b454060684caf664e15fbe89b7/asdf.lisp#L6802)

## SBCL

[sbcl/sbcl](https://github.com/sbcl/sbcl) `5ebd83dd58480aaf46e582f5e787705f491ef5ef`

- [`src/compiler/globaldb.lisp:182`](https://github.com/sbcl/sbcl/blob/5ebd83dd58480aaf46e582f5e787705f491ef5ef/src/compiler/globaldb.lisp#L182) `#+sb-xc-xhost`. The feature used everywhere else in that tree is `:sb-xc-host`. The error that comment says should fire while cross-compiling does not.
- [`src/compiler/ir2opt.lisp:695`](https://github.com/sbcl/sbcl/blob/5ebd83dd58480aaf46e582f5e787705f491ef5ef/src/compiler/ir2opt.lisp#L695) `#+(and x86-64 (or))`. The empty `(or)` is the usual way to comment a form out. Skiptrace reports it and says so.
- `#+sparc-64` and `#-sparc-64` in [`src/compiler/sparc/vm.lisp`](https://github.com/sbcl/sbcl/blob/5ebd83dd58480aaf46e582f5e787705f491ef5ef/src/compiler/sparc/vm.lisp#L209) and [`src/compiler/sparc/insts.lisp`](https://github.com/sbcl/sbcl/blob/5ebd83dd58480aaf46e582f5e787705f491ef5ef/src/compiler/sparc/insts.lisp#L949). Skiptrace suggests `:sparc64`. In this tree the `*features*` name is `:sparc`, and `:sparc-64` is used as a backend subfeature, not as a reader feature.

The vendored UIOP form is listed above.

## Clozure CL

[Clozure/ccl](https://github.com/Clozure/ccl) `ba7111836b41cd4e5df8b7682f8f78eee98c07e9`

- [`level-0/PPC/ppc-clos.lisp:55`](https://github.com/Clozure/ccl/blob/ba7111836b41cd4e5df8b7682f8f78eee98c07e9/level-0/PPC/ppc-clos.lisp#L55) `#+pp32-target`, next to `#+ppc64-target`. The `c` is missing.
- [`level-0/PPC/ppc-numbers.lisp:507`](https://github.com/Clozure/ccl/blob/ba7111836b41cd4e5df8b7682f8f78eee98c07e9/level-0/PPC/ppc-numbers.lisp#L507) `#+ppc32=target`, on the line after a correct `#+ppc32-target`.
- [`level-0/X86/x86-array.lisp:205`](https://github.com/Clozure/ccl/blob/ba7111836b41cd4e5df8b7682f8f78eee98c07e9/level-0/X86/x86-array.lisp#L205) `#-x8664-target` is still inside the [`#+x8664-target`](https://github.com/Clozure/ccl/blob/ba7111836b41cd4e5df8b7682f8f78eee98c07e9/level-0/X86/x86-array.lisp#L19) progn. `%init-misc` for other targets cannot be read.
- [`level-1/linux-files.lisp:1185`](https://github.com/Clozure/ccl/blob/ba7111836b41cd4e5df8b7682f8f78eee98c07e9/level-1/linux-files.lisp#L1185) `#+windows-target "nul"` is inside the [`#-windows-target`](https://github.com/Clozure/ccl/blob/ba7111836b41cd4e5df8b7682f8f78eee98c07e9/level-1/linux-files.lisp#L1125) progn.
- [`tools/defsystem.lisp:1499`](https://github.com/Clozure/ccl/blob/ba7111836b41cd4e5df8b7682f8f78eee98c07e9/tools/defsystem.lisp#L1499) `#+(and :sgi :cmu :sbcl)` requires three implementations at once.

The vendored UIOP forms are listed above.

## CLISP

[gnu-clisp/clisp](https://gitlab.com/gnu-clisp/clisp) `325f8a7000da86d6d991ceb4e81115c8968209fc`

- [`tests/mop-aux.lisp:720`](https://gitlab.com/gnu-clisp/clisp/-/blob/325f8a7000da86d6d991ceb4e81115c8968209fc/tests/mop-aux.lisp#L720), [`:877`](https://gitlab.com/gnu-clisp/clisp/-/blob/325f8a7000da86d6d991ceb4e81115c8968209fc/tests/mop-aux.lisp#L877), and [`:905`](https://gitlab.com/gnu-clisp/clisp/-/blob/325f8a7000da86d6d991ceb4e81115c8968209fc/tests/mop-aux.lisp#L905) are `#+clisp` and `#+sbcl` inside [`#-(or clisp sbcl)`](https://gitlab.com/gnu-clisp/clisp/-/blob/325f8a7000da86d6d991ceb4e81115c8968209fc/tests/mop-aux.lisp#L29). Those branches cannot be read.

The vendored UIOP forms are listed above.

## osicat

[osicat/osicat](https://github.com/osicat/osicat) `68732bd7ac69744303ac805e1bfbbbc02e49c0a3`

- [`src/osicat.lisp:152`](https://github.com/osicat/osicat/blob/68732bd7ac69744303ac805e1bfbbbc02e49c0a3/src/osicat.lisp#L152) `#+windows` is inside [`#-windows`](https://github.com/osicat/osicat/blob/68732bd7ac69744303ac805e1bfbbbc02e49c0a3/src/osicat.lisp#L144), in `%get-file-kind`.

## LTk

[ghollisjr/ltk](https://github.com/ghollisjr/ltk) `2ec6a1532b3ac60ea0805674af71f156bccf97f6`

- [`ltk/ginspect.lisp:222`](https://github.com/ghollisjr/ltk/blob/2ec6a1532b3ac60ea0805674af71f156bccf97f6/ltk/ginspect.lisp#L222) and [`:227`](https://github.com/ghollisjr/ltk/blob/2ec6a1532b3ac60ea0805674af71f156bccf97f6/ltk/ginspect.lisp#L227) are `#+scl` inside [`#+sbcl`](https://github.com/ghollisjr/ltk/blob/2ec6a1532b3ac60ea0805674af71f156bccf97f6/ltk/ginspect.lisp#L218). The function is read only on SBCL, so the Scieneer slots cannot be read.

## cl-cffi-gtk

[sharplispers/cl-cffi-gtk](https://github.com/sharplispers/cl-cffi-gtk) `1700fe672c65455c1fc33061ec92a3df84287ec7`

- [`gtk/gtk.drag-and-drop.lisp:869`](https://github.com/sharplispers/cl-cffi-gtk/blob/1700fe672c65455c1fc33061ec92a3df84287ec7/gtk/gtk.drag-and-drop.lisp#L869) and [`:1047`](https://github.com/sharplispers/cl-cffi-gtk/blob/1700fe672c65455c1fc33061ec92a3df84287ec7/gtk/gtk.drag-and-drop.lisp#L1047) use `#+cl-cffi-gtk-documenation`. The rest of the library spells that feature `cl-cffi-gtk-documentation`.

## SLIME and SLY

These are intentional. The empty `(or)` disables the form on every implementation, and the report says so.

- [SLIME `swank/ecl.lisp:1086`](https://github.com/slime/slime/blob/82dfda1a83e22de6fad93f54f3201f5dec6754fb/swank/ecl.lisp#L1086) `#+(and ecl-weak-hash (or))`, revision `82dfda1a83e22de6fad93f54f3201f5dec6754fb`
- [SLY `slynk/backend/ecl.lisp:1059`](https://github.com/joaotavora/sly/blob/191fe38eaa83e4e7556a940aa4b234666215cced/slynk/backend/ecl.lisp#L1059) `#+(and ecl-weak-hash (or))`, revision `191fe38eaa83e4e7556a940aa4b234666215cced`

## The other 232

232 source trees produced neither a contradiction nor a likely typo.

Representative examples:
Closer to MOP, Alexandria, cl-ppcre, CFFI, Bordeaux-Threads,
Hunchentoot, Ironclad, Iterate, Nyxt, Lem, pgloader, Coalton.

<details>
<summary>All 232 clean source trees</summary>

`1am`, `3bmd`, `McCLIM`, `Postmodern`, `access`, `alexandria`, `anaphora`, `april`, `archive`, `asdf-finalizers`, `asdf-system-connections`, `assoc-utils`, `atomics`, `babel`, `beirc`, `blackbird`, `bordeaux-threads`, `bt-semaphore`, `calispel`, `carrier`, `caveman`, `cepl`, `cerberus`, `cffi`, `chanl`, `check-it`, `chipz`, `chronicity`, `chunga`, `circular-streams`, `cl-annot`, `cl-annot-revisit`, `cl-async`, `cl-autowrap`, `cl-charms`, `cl-conspack`, `cl-cont`, `cl-containers`, `cl-cookie`, `cl-coveralls`, `cl-cpus`, `cl-cron`, `cl-css`, `cl-csv`, `cl-cuda`, `cl-dbi`, `cl-decimals`, `cl-fad`, `cl-fond`, `cl-gamepad`, `cl-glfw3`, `cl-html-parse`, `cl-html5-parser`, `cl-interpol`, `cl-jpeg`, `cl-json`, `cl-libuv`, `cl-log`, `cl-markdown`, `cl-markless`, `cl-markup`, `cl-memcached`, `cl-mime`, `cl-mixed`, `cl-mongo`, `cl-mpi`, `cl-oauth`, `cl-opengl`, `cl-pass`, `cl-pattern`, `cl-pdf`, `cl-plus-ssl`, `cl-ppcre`, `cl-project`, `cl-protobufs`, `cl-readline`, `cl-redis`, `cl-sdl2`, `cl-smtp`, `cl-sqlite`, `cl-store`, `cl-string-match`, `cl-strings`, `cl-syntax`, `cl-tls`, `cl-typesetting`, `cl-unicode`, `cl-vectors`, `cl-who`, `cl-yacc`, `clack`, `climacs`, `closer-mop`, `closure-common`, `closure-html`, `clunit2`, `clx`, `coalton`, `command-line-arguments`, `crane`, `croatoan`, `crypto-shortcuts`, `cxml`, `cxml-rpc`, `cxml-stp`, `datafly`, `defclass-std`, `deploy`, `dexador`, `dissect`, `djula`, `do-urlencode`, `documentation-utils`, `drakma`, `drakma-async`, `esrap`, `external-program`, `fare-mop`, `fare-quasiquote`, `fare-utils`, `fast-http`, `fast-io`, `fiasco`, `file-notify`, `fiveam`, `flexi-streams`, `function-cache`, `global-vars`, `harmony`, `http-body`, `hunchentoot`, `hunchentoot-auth`, `imago`, `inferior-shell`, `iolib`, `ironclad`, `iterate`, `jonathan`, `json-mop`, `jzon`, `lack`, `lass`, `legit`, `lem`, `let-plus`, `linedit`, `lisp-unit`, `lla`, `local-time`, `log4cl`, `lparallel`, `lquery`, `magicl`, `maxpc`, `md5`, `metabang-bind`, `mgl-pax`, `mito`, `mk-string-metrics`, `moptilities`, `myway`, `named-readtables`, `nibbles`, `ningle`, `nodgui`, `north`, `nyxt`, `one-more-re-nightmare`, `opticl`, `optima`, `parachute`, `parenscript`, `parse-float`, `parse-number`, `pathname-utils`, `petalisp`, `pgloader`, `plump`, `png-read`, `pngload`, `proc-parse`, `prove`, `puri`, `quri`, `rove`, `salza2`, `sanity-clause`, `secure-random`, `serapeum`, `series`, `shasht`, `sketch`, `skippy`, `smart-buffer`, `smug`, `spinneret`, `split-sequence`, `staple`, `static-vectors`, `stefil`, `stumpwm`, `swap-bytes`, `sxql`, `trivia`, `trivial-arguments`, `trivial-backtrace`, `trivial-benchmark`, `trivial-cltl2`, `trivial-features`, `trivial-file-size`, `trivial-garbage`, `trivial-gray-streams`, `trivial-indent`, `trivial-main-thread`, `trivial-mimes`, `trivial-package-local-nicknames`, `trivial-types`, `trivial-utf-8`, `uax-15`, `unix-opts`, `usocket`, `vecto`, `verbose`, `vom`, `woo`, `wookie`, `xsubseq`, `yason`, `zip`, `zpb-ttf`, `zpng`, `zs3`.

</details>

Count of that list plus the eleven with findings is 243.
