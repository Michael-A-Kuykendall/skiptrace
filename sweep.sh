#!/bin/sh
# 18-project smoke corpus. This is not the 243-tree scan in EXAMPLES.md.
# Run from the repo root (where bin/ is).
#   sh sweep.sh            -> clones into ./corpus, writes ./sweep/<lib>.txt
# Each report begins with the exact upstream commit that was scanned.
set -e
mkdir -p corpus sweep
for r in usocket/usocket sionescu/bordeaux-threads cffi/cffi slime/slime \
         trivial-features/trivial-features fare/asdf edicl/hunchentoot \
         sharplispers/ironclad Shinmera/dissect fukamachi/dexador \
         trivial-garbage/trivial-garbage sionescu/iolib Shinmera/deploy \
         cl-babel/babel sharplispers/split-sequence marijnh/Postmodern \
         sharplispers/chipz fukamachi/woo; do
  name=${r#*/}
  [ -d "corpus/$name" ] || git clone -q --depth 1 "https://github.com/$r.git" "corpus/$name"
  revision=$(git -C "corpus/$name" rev-parse HEAD)
  {
    printf 'upstream-revision: %s\n\n' "$revision"
    sbcl --script bin/skiptrace "corpus/$name" || true
  } > "sweep/$name.txt"
  printf '%-18s %s\n' "$name" "$(grep -E '^== (Impossible guard chains|Likely typos)' "sweep/$name.txt" | grep -oE '\([0-9]+\)' | tr '\n' ' ')"
done
echo "Columns: (contradictions) (likely typos). Full reports in sweep/."
