;;;; Print a skiptrace profile for the Lisp running this file.
;;;;
;;;;   sbcl --script dump-features.lisp > profiles/sbcl-linux-x86-64.sexp
;;;;   ccl -b -l dump-features.lisp -e '(quit)' > profiles/ccl-linux-x86-64.sexp
;;;;   ecl --shell dump-features.lisp > profiles/ecl-linux-x86-64.sexp
;;;;
;;;; Run it in the same kind of image you ship (with ASDF/Quicklisp loaded if you
;;;; load them), since loading those pushes features too.

(let ((name (format nil "~(~a~)-~(~a~)-~(~a~)"
                    (lisp-implementation-type) (software-type) (machine-type))))
  (setf name (substitute #\- #\Space name))
  (let ((*print-case* :downcase) (*print-right-margin* 80) (*package* (find-package :keyword)))
    (format t "(:name ~s~% :source ~s~% :features ~s)~%"
            name
            (format nil "captured from ~a ~a" (lisp-implementation-type) (lisp-implementation-version))
            (copy-list *features*))))
