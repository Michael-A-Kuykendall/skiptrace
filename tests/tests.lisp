;;;; Tests. Run:  sbcl --script tests/run.lisp

(defpackage #:skiptrace-tests
  (:use #:common-lisp #:skiptrace)
  (:export #:run-tests))

(in-package #:skiptrace-tests)

(defvar *failures* 0)
(defvar *count* 0)
(declaim (special *skiptrace-dump-quiet*))
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

  ;; dump-features.lisp prints a profile when loaded as a script.
  (let ((*skiptrace-dump-quiet* t)
        (*standard-output* (make-broadcast-stream))
        (*error-output* (make-broadcast-stream)))
    (load (merge-pathnames "../dump-features.lisp" *profiles-dir*)))
  (check "clisp software-type is not a profile name"
         (cl-user::skiptrace-dump-name
          "CLISP"
          "gcc -g -O2 -ffile-prefix-map=/build/clisp/src"
          "X86_64")
         "clisp-x86-64")
  (check "sane dump name keeps software and machine"
         (list (cl-user::skiptrace-dump-name "SBCL" "Linux" "X86-64")
               (cl-user::skiptrace-dump-name "ECL" "Linux" "x86_64"))
         '("sbcl-linux-x86-64" "ecl-linux-x86-64"))

  (let* ((demo (namestring (merge-pathnames "../examples/demo.lisp" *profiles-dir*)))
         (analysis (nth-value 2 (skiptrace:audit-paths (list demo) :profile-dir *profiles-dir*)))
         (text (with-output-to-string (out)
                 (skiptrace::report-json nil analysis :stream out)))
         (keys '()))
    (let ((start 0))
      (loop
        (let* ((nl (position #\Newline text :start start))
               (line (subseq text start (or nl (length text)))))
          (when (and (>= (length line) 4)
                     (char= (char line 0) #\Space)
                     (char= (char line 1) #\Space)
                     (char= (char line 2) #\"))
            (push (subseq line 3 (position #\" line :start 3)) keys))
          (unless nl (return))
          (setf start (1+ nl)))))
    (check "json schema stays thin"
           (nreverse keys)
           '("profiles" "sites" "likely_typos")))

  (labels ((quiet-main (args)
             (let (code)
               (with-output-to-string (*standard-output*)
                 (with-output-to-string (*error-output*)
                   (setf code (handler-case
                                  (skiptrace:main args :default-profile-dir *profiles-dir*)
                                (error () 2)))))
               code)))
    (let ((examples (namestring (merge-pathnames "../examples/" *profiles-dir*)))
          (lone #p"/tmp/skiptrace-untested-only.lisp"))
      (with-open-file (out lone :direction :output :if-exists :supersede
                           :if-does-not-exist :create)
        (write-string "#+lispworks (foo)" out))
      (unwind-protect
           (check "exit codes"
                  (list (quiet-main (list examples))
                        (quiet-main (list "--strict" examples))
                        (quiet-main (list "--strict" (namestring lone)))
                        (quiet-main (list "/tmp/skiptrace-missing-path-that-does-not-exist"))
                        (quiet-main nil))
                  '(0 1 0 2 2))
        (ignore-errors (delete-file lone)))))

  (check "character literal hides sharpsign" (summary "(list #\\ #+sbcl x)") '())
  (check "character literal ends at one character"
         (summary "(list #\\  #+sbcl x)")
         '((1 "#+sbcl" "x" nil)))

  (let* ((demo (namestring (merge-pathnames "../examples/demo.lisp" *profiles-dir*)))
         (analysis (nth-value 2 (skiptrace:audit-paths (list demo) :profile-dir *profiles-dir*)))
         (hits (getf analysis :contradictions))
         (typos (getf analysis :typos)))
    (check "demo keeps its known findings"
           (list (length hits)
                 (and hits (site-line (first hits)))
                 (and hits (not (null (search "demo.lisp" (site-file (first hits))))))
                 (mapcar (lambda (x) (list (first x) (second x))) typos))
           (list 1 16 t '((:sb_thread :sb-thread)))))

  (check "setf adjoin is not a recorded push"
         (skiptrace::find-pushed-features "(setf *features* (adjoin :ghost *features*))")
         nil)
  (check "version>= stays unknown"
         (list (fx "(version>= 10 1)") (ev "(version>= 10 1)" '()))
         '((:bad "(version>= 10 1)") :unknown))

  (labels ((first-line (text)
             (let* ((result (skiptrace::scan-text text "t.lisp"))
                    (profiles (skiptrace:load-profiles *profiles-dir*))
                    (analysis (skiptrace::analyze (list result) profiles nil))
                    (out (with-output-to-string (s)
                           (skiptrace::report-text (list result) profiles analysis :stream s))))
               (subseq out 0 (position #\Newline out)))))
    (let* ((examples (namestring (merge-pathnames "../examples/" *profiles-dir*)))
           (reported (with-output-to-string (*standard-output*)
                       (skiptrace:main (list examples) :default-profile-dir *profiles-dir*))))
      (check "report opens with defect counts"
             (list (subseq reported 0 (position #\Newline reported))
                   (first-line "#+(or) (commented)"))
             '("skiptrace: 1 contradiction, 1 typo"
               "skiptrace: 0 contradictions, 0 typos"))))

  (labels ((write-profile (dir name source)
             (ensure-directories-exist (merge-pathnames "x.sexp" dir))
             (with-open-file (out (merge-pathnames (concatenate 'string name ".sexp") dir)
                                  :direction :output :if-exists :supersede
                                  :if-does-not-exist :create)
               (format out "(:name ~s :source ~s :features (:common-lisp))~%" name source))))
    (let ((cap (merge-pathnames "skiptrace-prof-cap/"
                                (make-pathname :directory '(:absolute "tmp"))))
          (hand (merge-pathnames "skiptrace-prof-hand/"
                                 (make-pathname :directory '(:absolute "tmp")))))
      (write-profile cap "zebra" "captured from TestLisp 1.0; notes mention approximate builds")
      (write-profile hand "hand" "approximate, written by hand")
      (unwind-protect
           (progn
             (check "captured source may mention approximate"
                    (mapcar #'skiptrace::profile-name (skiptrace:load-profiles cap))
                    '("zebra"))
             (check "handwritten source stays out of the default matrix"
                    (mapcar #'skiptrace::profile-name (skiptrace:load-profiles hand))
                    nil))
        (dolist (dir (list cap hand))
          (dolist (file (ignore-errors (directory (merge-pathnames "*.sexp" dir))))
            (ignore-errors (delete-file file)))))))

  (format t "~a/~a checks passed~%" (- *count* *failures*) *count*)
  (zerop *failures*))
