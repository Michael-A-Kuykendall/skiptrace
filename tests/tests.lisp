;;;; Tests. Run:  sbcl --script tests/run.lisp

(defpackage #:skiptrace-tests
  (:use #:common-lisp #:skiptrace)
  (:export #:run-tests))

(in-package #:skiptrace-tests)

(defvar *failures* 0)
(defvar *count* 0)
(defvar *profiles-dir*
  (or (let ((asdf (find-package :asdf)))
        (when asdf
          (let ((fn (find-symbol "SYSTEM-RELATIVE-PATHNAME" asdf)))
            (when (fboundp fn)
              (let ((dir (ignore-errors (funcall fn :skiptrace "profiles/"))))
                (when (and dir
                           (probe-file (merge-pathnames "sbcl-linux-x86-64.sexp" dir)))
                  dir))))))
      (merge-pathnames "../profiles/"
                       (make-pathname :name nil :type nil :defaults *load-truename*))))

(defmacro check (name form expected)
  `(let ((got (handler-case ,form (error (e) (list :error (princ-to-string e)))))
         (want ,expected))
     (incf *count*)
     (unless (equal got want)
       (incf *failures*)
       (format t "FAIL ~a~%  expected ~s~%  got      ~s~%" ,name want got))))

(defun sites-of (text &key asd)
  (skiptrace::fr-sites (skiptrace::scan-text text "t.lisp" :asd asd)))

(defun summary (text &key asd)
  "List of (line guard-string preview parent-line) for each site in TEXT."
  (mapcar (lambda (s)
            (list (site-line s) (skiptrace::site-guard-string s) (site-preview s)
                  (and (site-parent s) (site-line (site-parent s)))))
          (sites-of text :asd asd)))

(defun fx (s) (parse-feature-expression s))
(defun ev (s features) (eval-feature-expression (fx s) features))

(defun nested-walk-names ()
  "Write a source file one directory down and collect it. ECL used to miss this."
  (let* ((root (merge-pathnames "skiptrace-nest-fixture/"
                                (make-pathname :directory '(:absolute "tmp"))))
         (leaf (merge-pathnames "sub/leaf.lisp" root)))
    (ensure-directories-exist leaf)
    (with-open-file (out leaf :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (write-string "#+sbcl (nested)" out))
    (unwind-protect
         (sort (mapcar #'cdr (skiptrace::collect-files root)) #'string<)
      (ignore-errors (delete-file leaf)))))

(defun run-tests ()
  (setf *failures* 0 *count* 0)

  ;; Feature expression parsing
  (check "keyword" (fx ":sbcl") :sbcl)
  (check "bare symbol" (fx "sbcl") :sbcl)
  (check "lowercase and" (fx "(and sbcl (not win32))") '(:and :sbcl (:not :win32)))
  (check "package-qualified operator" (fx "(cl:or :ccl :ecl)") '(:or :ccl :ecl))
  (check "empty or" (fx "(or)") '(:or))
  (check "escaped case" (fx "|Foo|") (intern "Foo" :keyword))
  (check "read-eval" (fx "#.(cl:if t '(and) '(or))") '(:dynamic))
  (check "garbage" (fx "(sbcl ccl)") '(:bad "(sbcl ccl)"))
  (check "not arity" (fx "(not a b)") '(:bad "(not a b)"))

  ;; Evaluation
  (check "true" (ev ":sbcl" '(:sbcl)) :true)
  (check "false" (ev ":sbcl" '(:ccl)) :false)
  (check "or empty false" (ev "(or)" '(:sbcl)) :false)
  (check "and empty true" (ev "(and)" '()) :true)
  (check "not" (ev "(not win32)" '(:linux)) :true)
  (check "unknown propagates" (ev "(and :sbcl #.(foo))" '(:sbcl)) :unknown)

  ;; Scanner: things that must NOT produce sites
  (check "in string" (summary "(print \"#+sbcl not code\")") '())
  (check "in line comment" (summary "; #+sbcl (foo)
(bar)") '())
  (check "in nested block comment" (summary "#| outer #| inner |# #+sbcl (x) |# (y)") '())
  (check "char literal paren" (summary "(list #\\( #\\) #\\\") #+ccl (z)")
         '((1 "#+ccl" "(z)" nil)))
  (check "escaped symbol" (summary "(|weird ) symbol| #+ecl a)")
         '((1 "#+ecl" "a" nil)))

  ;; Scanner: structure
  (check "simple"
         (summary "#+sbcl
(defun foo ())
#-sbcl (defun foo () 1)")
         '((1 "#+sbcl" "(defun foo ())" nil) (3 "#-sbcl" "(defun foo () 1)" nil)))
  (check "nested guard has parent"
         (summary "#+sbcl
(progn
  #+linux (a)
  #+win32 (b))")
         '((1 "#+sbcl" "(progn" nil) (3 "#+linux" "(a)" 1) (4 "#+win32" "(b)" 1)))
  (check "stacked guards nest"
         (summary "#+sbcl #+linux (x)")
         '((1 "#+sbcl" "#+linux (x)" nil) (1 "#+linux" "(x)" 1)))
  (check "end line recorded"
         (site-end-line (first (sites-of "#+sbcl
(defun foo ()
  1)")))
         3)
  (check "quote and function prefixes"
         (summary "(list '#+sbcl a #'#+ccl b `(,@#+ecl c))")
         '((1 "#+sbcl" "a" nil) (1 "#+ccl" "b" nil) (1 "#+ecl" "c" nil)))
  (check "unknown reader macro treated as prefix"
         (summary "(#?\"#+sbcl ${x}\" #+ccl y)")
         '((1 "#+ccl" "y" nil)))
  (check "shebang line ignored"
         (summary "#!/usr/bin/env sbcl --script
#+sbcl (main)")
         '((2 "#+sbcl" "(main)" nil)))
  (check "comment idiom flagged"
         (mapcar #'site-comment-p (sites-of "#+(or) (a) #-(and) (b) #+nil (c) #+ignore (e) #+sbcl (d)"))
         '(t t t t nil))
  (check "asdf if-feature"
         (summary "(defsystem \"x\" :components ((:file \"a\") (:file \"b\" :if-feature (:and :sbcl :unix))))"
                  :asd t)
         '((1 ":if-feature (and sbcl unix)" "(:file \"b\" :if-feature (:and :sbcl :unix))))" nil)))
  (check "if-feature ignored outside asd"
         (summary "(foo :if-feature :sbcl)") '())

  ;; Pushed features
  (check "pushed features"
         (sort (mapcar #'symbol-name
                       (skiptrace::find-pushed-features
                        "(pushnew :my-lib *features*) (push :other cl:*features*) (pushnew x *features*)"))
               #'string<)
         '("MY-LIB" "OTHER"))
  (check "push in comment ignored"
         (sort (mapcar #'symbol-name
                       (skiptrace::find-pushed-features
                        ";; (pushnew :ghost *features*)
(pushnew :real *features*)"))
               #'string<)
         '("REAL"))
  (check "push in string ignored"
         (sort (mapcar #'symbol-name
                       (skiptrace::find-pushed-features
                        "(print \"(pushnew :ghost *features*)\") (pushnew :real *features*)"))
               #'string<)
         '("REAL"))

  ;; Typo detection: conservative on purpose
  (check "typo underscore" (skiptrace::near-miss :sb_thread '(:sb-thread :sbcl)) :sb-thread)
  (check "typo swap" (skiptrace::near-miss :linxu '(:linux :unix)) :linux)
  (check "version is not a typo" (skiptrace::near-miss :lispworks4 '(:lispworks)) nil)
  (check "digit change is not a typo" (skiptrace::near-miss :32-bit-host '(:64-bit-host)) nil)
  (check "suffix is not a typo" (skiptrace::near-miss :solaris2 '(:solaris)) nil)
  (check "no false match" (skiptrace::near-miss :my-feature '(:linux :sbcl)) nil)
  (check "version feature" (skiptrace::version-feature-of :lispworks4.1) "LISPWORKS")
  (check "version feature dash" (skiptrace::version-feature-of :ccl-5.2) "CCL")
  (check "not a version feature" (skiptrace::version-feature-of :lispworks) nil)

  ;; Whole pipeline on a fixture with known answers
  (let* ((profiles (list (skiptrace::make-profile :name "a" :features '(:sbcl :linux :unix))
                         (skiptrace::make-profile :name "b" :features '(:ccl :linux :unix))))
         (results (list (skiptrace::scan-text "#+sbcl (a)
#+ccl (b)
#+(and sbcl ccl) (never)
#+lispworks (lw)
#+sbcl #+win32 (sbcl-windows)
#+linxu (typo)
#+(or) (commented)
#+my-lib (mine)
(pushnew :my-lib *features*)
#-(or sbcl ccl) (error \"unsupported\")
#+sbcl
(progn
  #+openmcl (impossible))
#+ignore (also-commented)" "f.lisp")))
         (an (skiptrace::analyze results profiles '()))
         (lines (lambda (key) (mapcar #'site-line (getf an key))))
         (untested (sort (loop for k being the hash-keys of (getf an :untested) collect (symbol-name k))
                         #'string<)))
    (check "contradictions" (funcall lines :contradictions) '(3 13))
    (check "never read in matrix" (funcall lines :matrix-dead) '(10))
    (check "untested features" untested '("LINXU" "LISPWORKS" "WIN32"))
    (check "typos" (mapcar (lambda (x) (list (first x) (second x))) (getf an :typos)) '((:linxu :linux)))
    (check "comment sites" (length (getf an :comment-sites)) 2)
    (check "pushed feature is can't-tell, not dead"
           (skiptrace::read-status (find 8 (getf an :live) :key #'site-line)
                                       (first (getf an :profiles)))
           :unknown)
    (check "maybe" (eval-feature-expression :x '() '(:x)) :unknown)
    (check "maybe under not" (eval-feature-expression '(:not :x) '() '(:x)) :unknown))

  (check "walks a nested source file"
         (nested-walk-names)
         '("sub/leaf.lisp"))

  (check "default matrix is the captured profiles"
         (sort (mapcar #'skiptrace::profile-name (skiptrace:load-profiles *profiles-dir*))
               #'string<)
         '("clisp-linux-x86-64" "ecl-linux-x86-64" "sbcl-linux-x86-64"))
  (check "named handwritten profile still loads"
         (mapcar #'skiptrace::profile-name
                 (skiptrace:load-profiles *profiles-dir* '("ccl-linux-x86-64")))
         '("ccl-linux-x86-64"))

  (format t "~a/~a checks passed~%" (- *count* *failures*) *count*)
  (zerop *failures*))
