;;;; Scan many directories in one SBCL process. One JSON object per line.
;;;;   sbcl --script bin/corpus-batch.lisp PROFILE-DIR JOBS.tsv OUT.jsonl
;;;; Each jobs line is project<TAB>directory. A bad directory is one error line.
;;;; The rest of the jobs still run.

(let* ((*load-verbose* nil)
       (*load-print* nil)
       (here (make-pathname :name nil :type nil :defaults *load-truename*))
       (root (merge-pathnames (make-pathname :directory '(:relative :up)) here)))
  (load (merge-pathnames "src/skiptrace.lisp" root)))

(in-package #:skiptrace)

(defun batch-args ()
  #+sbcl (let ((tail (rest sb-ext:*posix-argv*)))
           (if (and tail (string= (first tail) "--")) (rest tail) tail))
  #-sbcl (error "corpus-batch runs on SBCL"))

(defun write-project-line (stream project results analysis err)
  (write-char #\{ stream)
  (json-string "project" stream)
  (write-string ":" stream)
  (json-string project stream)
  (format stream ",\"files\":~a,\"forms\":~a,\"error\":"
          (length results)
          (if analysis (length (getf analysis :sites)) 0))
  (if err
      (json-string err stream)
      (write-string "null" stream))
  (write-string ",\"report\":" stream)
  (if analysis
      (let ((body (with-output-to-string (s)
                    (report-json-full results nil analysis :stream s))))
        (loop for c across body
              unless (or (char= c #\Newline) (char= c #\Return))
              do (write-char c stream)))
      (write-string "null" stream))
  (write-line "}" stream)
  (finish-output stream))

(defun run-batch (profile-dir jobs out-path)
  (let ((n 0))
    (with-open-file (out out-path :direction :output :if-exists :supersede
                             :if-does-not-exist :create)
      (with-open-file (in jobs)
        (loop for line = (read-line in nil nil)
              while line
              do (when (and (plusp (length line)) (find #\Tab line))
                   (let* ((tab (position #\Tab line))
                          (project (subseq line 0 tab))
                          (dir (subseq line (1+ tab))))
                     (incf n)
                     (when (zerop (mod n 100))
                       (format *error-output* "progress ~a ~a~%" n project)
                       (finish-output *error-output*))
                     (handler-case
                         (multiple-value-bind (results profiles analysis)
                             (audit-paths (list dir) :profile-dir profile-dir)
                           (declare (ignore profiles))
                           (write-project-line out project results analysis nil))
                       (error (e)
                         (write-project-line out project nil nil (princ-to-string e)))))))))))

(let ((args (batch-args)))
  (unless (= (length args) 3)
    (format *error-output* "Usage: corpus-batch PROFILE-DIR JOBS.tsv OUT.jsonl~%")
    #+sbcl (sb-ext:exit :code 2))
  (run-batch (pathname (concatenate 'string (string-right-trim "/" (first args)) "/"))
             (second args)
             (third args))
  #+sbcl (sb-ext:exit :code 0))
