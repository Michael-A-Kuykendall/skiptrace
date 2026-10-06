;;;; A file with one of each problem feature-audit looks for.
;;;; sbcl --script bin/feature-audit.lisp examples/

(defpackage #:demo (:use #:cl))
(in-package #:demo)

;; Fine: each implementation gets a branch.
(defun thread-count ()
  #+sbcl (length (sb-thread:list-all-threads))
  #+ccl (length (ccl:all-processes))
  #-(or sbcl ccl) 1)

;; Contradiction: the inner guard can never be true inside the outer one.
#+sbcl
(defun fast-path ()
  #+ccl (ccl::%fast-thing)
  :slow)

;; Typo: :sb_thread is not a feature anywhere, so this code silently vanishes.
#+sb_thread
(defun start-worker () (sb-thread:make-thread (lambda ())))

;; Only read on SBCL for Windows, which you may never test.
#+(and sbcl win32)
(defun windows-only () :win)

;; Risky comment idiom.
#+nil
(defun old-version () :old)

;; Safe comment idiom; not reported.
#+(or)
(defun older-version () :older)
