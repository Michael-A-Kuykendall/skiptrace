;;;; ecl --shell tests/run-asdf.lisp
;;;; clisp -q -norc tests/run-asdf.lisp
;;;;
;;;; The file is not named asdf.lisp: CLISP's (require "asdf") would load a
;;;; file of that name from this directory and recurse.
;;;; CLISP's require takes the module name as a string. (require :asdf) looks
;;;; for a file named ASDF and fails.
(let ((*load-verbose* nil)
      (*load-print* nil)
      (root (merge-pathnames (make-pathname :directory '(:relative :up))
                             (make-pathname :name nil :type nil :defaults *load-truename*))))
  #+clisp (require "asdf")
  #-clisp (require :asdf)
  (funcall (find-symbol "LOAD-ASD" "ASDF") (merge-pathnames "skiptrace.asd" root))
  (funcall (find-symbol "TEST-SYSTEM" "ASDF") "skiptrace"))
