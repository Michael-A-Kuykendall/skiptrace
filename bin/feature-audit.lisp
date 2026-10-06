;;;; Command-line launcher.  sbcl --script bin/feature-audit.lisp [options] PATH...
;;;; Also: ecl --shell bin/feature-audit.lisp PATH...
;;;;       clisp bin/feature-audit.lisp PATH...
;;;;       ccl -b -l bin/feature-audit.lisp -- PATH...

(let* ((*load-verbose* nil)
       (*load-print* nil)
       (here (make-pathname :name nil :type nil :defaults *load-truename*))
       (root (merge-pathnames (make-pathname :directory '(:relative :up)) here)))
  (load (merge-pathnames "src/feature-audit.lisp" root))
  (labels ((script-tail (argv)
             "Arguments after this script. ECL keeps the script path in COMMAND-ARGS;
`--` is accepted too, so an explicit separator still works."
             (let ((dash (member "--" argv :test #'string=))
                   (script (and *load-truename* (namestring *load-truename*))))
               (cond (dash (rest dash))
                     ((and script (member script argv :test #'equal))
                      (rest (member script argv :test #'equal)))
                     (script
                      (loop for tail on argv
                            for arg = (car tail)
                            when (and (plusp (length arg))
                                      (<= (length arg) (length script))
                                      (string= script arg :start1 (- (length script) (length arg)))
                                      (or (= (length script) (length arg))
                                          (char= (char script (- (length script) (length arg) 1)) #\/)))
                            return (rest tail)))))))
    (let* ((args #+sbcl (rest sb-ext:*posix-argv*)
                 #+ccl (rest (member "--" ccl:*command-line-argument-list* :test #'string=))
                 #+ecl (script-tail (ext:command-args))
                 #+clisp ext:*args*
                 #-(or sbcl ccl ecl clisp) (error "Add argument handling for this Lisp"))
         (code (handler-case
                   (funcall (find-symbol "MAIN" "FEATURE-AUDIT") args
                            :default-profile-dir (merge-pathnames "profiles/" root))
                 (error (e)
                   (format *error-output* "feature-audit: ~a~%" e)
                   2))))
      (finish-output)
      #+sbcl (sb-ext:exit :code code)
      #+ccl (ccl:quit code)
      #+ecl (ext:quit code)
      #+clisp (ext:quit code))))
