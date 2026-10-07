;;;; Print a skiptrace profile for the Lisp running this file.
;;;;
;;;;   sbcl --script dump-features.lisp > profiles/sbcl-linux-x86-64.sexp
;;;;   ccl -b -l dump-features.lisp -e '(quit)' > profiles/ccl-linux-x86-64.sexp
;;;;   ecl --shell dump-features.lisp > profiles/ecl-linux-x86-64.sexp
;;;;   clisp -q -norc dump-features.lisp > profiles/clisp-linux-x86-64.sexp
;;;;
;;;; Run it in the same kind of image you ship (with ASDF/Quicklisp loaded if you
;;;; load them), since loading those pushes features too.
;;;;
;;;; CLISP's SOFTWARE-TYPE is the gcc command that built the image, followed by
;;;; the memory model, not the operating system. A component that contains
;;;; whitespace, a slash, or "gcc" is left out of :name. *features* is copied
;;;; as the running image has it. This file does not add :linux or :x86-64.
;;;; Set *skiptrace-dump-host* to a string such as "linux-x86-64" only after
;;;; you have identified that machine yourself.

(defvar *skiptrace-dump-host* nil
  "Optional host suffix for :name. Nil keeps only tokens that survive the filter.")

(defvar *skiptrace-dump-quiet* nil
  "When true, loading this file defines the name builder and prints nothing.")

(defun skiptrace-dump-unusable-p (raw)
  "True when RAW is a compiler command or a path, not a name token."
  (when raw
    (let ((text (string raw)))
      (flet ((has (ch) (find ch text)))
        (or (zerop (length text))
            (has #\Space)
            (has #\Newline)
            (has #\Tab)
            (has #\Return)
            (has #\/)
            (search "gcc" text :test #'char-equal))))))

(defun skiptrace-dump-token (raw)
  "Downcase RAW and collapse each run of non-alphanumeric characters to one hyphen."
  (let ((text (string-downcase (string raw)))
        (out (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
        (hyphen nil))
    (loop for ch across text
          do (cond ((alphanumericp ch)
                    (vector-push-extend ch out)
                    (setf hyphen nil))
                   ((not hyphen)
                    (vector-push-extend #\- out)
                    (setf hyphen t))))
    (string-trim '(#\-) out)))

(defun skiptrace-dump-name (implementation software machine &optional host)
  "Profile :name. Unusable software or machine components are omitted."
  (let ((parts '()))
    (dolist (raw (list implementation software machine host))
      (unless (skiptrace-dump-unusable-p raw)
        (let ((token (and raw (skiptrace-dump-token raw))))
          (when (and token (plusp (length token)))
            (push token parts)))))
    (format nil "~{~a~^-~}" (nreverse parts))))

(unless *skiptrace-dump-quiet*
  (let* ((name (skiptrace-dump-name (lisp-implementation-type)
                                    (software-type)
                                    (machine-type)
                                    *skiptrace-dump-host*))
         (*print-case* :downcase)
         (*print-right-margin* 80)
         (*package* (find-package :keyword)))
    (format t "(:name ~s~% :source ~s~% :features ~s)~%"
            name
            (format nil "captured from ~a ~a"
                    (lisp-implementation-type)
                    (lisp-implementation-version))
            (copy-list *features*))))
