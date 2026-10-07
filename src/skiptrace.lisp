;;;; skiptrace.lisp -- scan #+/#- and ASDF :if-feature without reading the file.
;;;;
;;;; The scanner does not call READ on the file it audits, and it does not use
;;;; Eclector. Profile files are the exception: read-profile binds *read-eval*
;;;; to NIL and reads one plist.
;;;;
;;;; Zero dependencies. The package uses only COMMON-LISP.
;;;;
;;;; After #\ the next character is part of the character name.
;;;;
;;;; A site records one #+ , #- , or ASDF :if-feature.
;;;;
;;;; The text report's wording lives in the format strings in report-text.

(defpackage #:skiptrace
  (:use #:common-lisp)
  (:export #:main #:audit-paths #:scan-file #:parse-feature-expression
           #:eval-feature-expression #:load-profiles
           #:site #:site-file #:site-line #:site-column #:site-kind #:site-expr
           #:site-raw #:site-parent #:site-preview #:site-end-line #:site-comment-p))

(in-package #:skiptrace)

;;; ------------------------------------------------------------------
;;; Data

(defstruct site
  file          ; display name
  line column   ; 1-based line, 0-based column of the #
  kind          ; :plus, :minus, or :if-feature
  expr          ; parsed feature expression
  raw           ; feature expression as written
  parent        ; nearest enclosing site, or NIL
  preview       ; first line of the guarded form
  (end-line nil)
  (comment-p nil)) ; #+(or) / #-(and) / #+nil idioms

(defstruct profile name source features (maybe '()))

(defstruct (file-result (:conc-name fr-))
  name sites pushed-features notes)

;;; ------------------------------------------------------------------
;;; Feature expressions

(defun fx-head-p (x) (member x '(:and :or :not)))

(defun parse-feature-expression (text)
  "Parse the text of a feature expression into keywords and (:AND ...) / (:OR ...) /
(:NOT x) lists. Read-time evaluation (#.) becomes (:DYNAMIC); garbage becomes (:BAD text)."
  (let ((pos 0) (len (length text)))
    (labels ((ws ()
               "Skip whitespace and comments. A feature expression is read with the normal reader."
               (loop
                 (when (>= pos len) (return))
                 (let ((c (char text pos)))
                   (cond ((whitespacep c) (incf pos))
                         ((char= c #\;)
                          (loop while (and (< pos len) (char/= (char text pos) #\Newline))
                                do (incf pos)))
                         ((and (char= c #\#) (< (1+ pos) len) (char= (char text (1+ pos)) #\|))
                          (incf pos 2)
                          (let ((depth 1))
                            (loop while (and (< pos len) (> depth 0))
                                  do (cond ((and (< (1+ pos) len)
                                                  (char= (char text pos) #\|)
                                                  (char= (char text (1+ pos)) #\#))
                                             (decf depth)
                                             (incf pos 2))
                                            ((and (< (1+ pos) len)
                                                  (char= (char text pos) #\#)
                                                  (char= (char text (1+ pos)) #\|))
                                             (incf depth)
                                             (incf pos 2))
                                            (t (incf pos))))))
                         (t (return))))))
             (item ()
               (ws)
               (when (>= pos len) (throw 'bad nil))
               (let ((c (char text pos)))
                 (cond ((char= c #\()
                        (incf pos)
                        (let ((elts (loop do (ws)
                                          until (or (>= pos len) (char= (char text pos) #\)))
                                          collect (item))))
                          (when (>= pos len) (throw 'bad nil))
                          (incf pos)
                          (cond ((and elts (fx-head-p (first elts))
                                      (every (lambda (e) (or (keywordp e) (consp e))) (rest elts)))
                                 (when (and (eq (first elts) :not) (/= (length elts) 2))
                                   (throw 'bad nil))
                                 elts)
                                (t (throw 'bad nil)))))
                       ((and (char= c #\#) (< (1+ pos) len) (char= (char text (1+ pos)) #\.))
                        (setf pos len)
                        (throw 'dynamic nil))
                       (t (symbol-item)))))
             (symbol-item ()
               (let ((start pos)
                     (out (make-string-output-stream))
                     (count 0)
                     (last-package-colon nil))
                 (labels ((emit (c escaped-p)
                            (when (and (not escaped-p) (char= c #\:))
                              (setf last-package-colon count))
                            (write-char (if escaped-p c (char-upcase c)) out)
                            (incf count)))
                   ;; FOR after WHILE is not portable; CLISP rejects it.
                   (loop
                     (unless (< pos len) (return))
                     (let ((c (char text pos)))
                       (when (or (whitespacep c) (member c '(#\( #\) #\;))) (return))
                       (cond ((char= c #\|)
                              (incf pos)
                              (loop
                                (when (>= pos len) (throw 'bad nil))
                                (let ((d (char text pos)))
                                  (cond ((char= d #\|)
                                         (incf pos)
                                         (return))
                                        ((char= d #\\)
                                         (when (>= (1+ pos) len) (throw 'bad nil))
                                         (emit (char text (1+ pos)) t)
                                         (incf pos 2))
                                        (t
                                         (emit d t)
                                         (incf pos))))))
                             ((char= c #\\)
                              (when (>= (1+ pos) len) (throw 'bad nil))
                              (emit (char text (1+ pos)) t)
                              (incf pos 2))
                             (t
                              (emit c nil)
                              (incf pos)))))
                   (when (= start pos) (throw 'bad nil))
                   (let ((name (get-output-stream-string out)))
                     ;; :sbcl, sbcl, keyword:sbcl, cl:and all mean the same thing here.
                     ;; A colon protected by |...| or \ is symbol data, not a package marker.
                     (when last-package-colon
                       (setf name (subseq name (1+ last-package-colon))))
                     (when (zerop (length name)) (throw 'bad nil))
                     (intern name :keyword))))))
      (catch 'dynamic
        (catch 'bad
          (let ((result (item)))
            (ws)
            (return-from parse-feature-expression
              (if (< pos len) (list :bad text) result))))
        (return-from parse-feature-expression (list :bad text)))
      (list :dynamic))))

(defun eval-feature-expression (expr features &optional maybe)
  "Three-valued: :TRUE, :FALSE, or :UNKNOWN. Features in MAYBE might or might not be
present (the code pushes them itself, perhaps conditionally); #. and unparseable
expressions are also :UNKNOWN."
  (cond ((keywordp expr) (cond ((member expr features) :true)
                               ((member expr maybe) :unknown)
                               (t :false)))
        ((member (first expr) '(:dynamic :bad)) :unknown)
        (t (let ((vals (mapcar (lambda (e) (eval-feature-expression e features maybe)) (rest expr))))
             (ecase (first expr)
               (:not (case (first vals) (:true :false) (:false :true) (t :unknown)))
               (:and (cond ((member :false vals) :false)
                           ((member :unknown vals) :unknown)
                           (t :true)))
               (:or (cond ((member :true vals) :true)
                          ((member :unknown vals) :unknown)
                          (t :false))))))))

(defun fx-atoms (expr)
  (cond ((keywordp expr) (list expr))
        ((member (first expr) '(:dynamic :bad)) nil)
        (t (remove-duplicates (mapcan #'fx-atoms (rest expr))))))

(defun fx-to-string (expr)
  (cond ((keywordp expr) (string-downcase (symbol-name expr)))
        ((eq (first expr) :dynamic) "#.(...)")
        ((eq (first expr) :bad) (second expr))
        (t (format nil "(~(~a~)~{ ~a~})" (first expr) (mapcar #'fx-to-string (rest expr))))))

(defun comment-idiom-p (kind expr)
  (or (and (eq kind :plus) (equal expr '(:or)))
      (and (eq kind :minus) (equal expr '(:and)))
      (and (eq kind :plus) (member expr '(:nil :ignore)) t)))

;;; ------------------------------------------------------------------
;;; Source scanner
;;;
;;; Walks the text the way the reader would without calling READ on audited source.
;;; It only needs to know where each object starts and ends, and where #+/#- appear.
;;; Bound by scan-text for the duration of one file.

(defvar *text*)
(defvar *len*)
(defvar *file*)
(defvar *line-starts*)
(defvar *sites*)
(defvar *notes*)
(defvar *asd-p*)
(defvar *recording* t)
(defvar *pushed-features* nil)

(defun whitespacep (c)
  (member c '(#\Space #\Tab #\Newline #\Return #\Page #\Linefeed)))

(defun terminatingp (c)
  (or (whitespacep c) (member c '(#\( #\) #\" #\' #\` #\, #\;))))

(defun compute-line-starts (text)
  (let ((v (make-array 64 :adjustable t :fill-pointer 0)))
    (vector-push-extend 0 v)
    (loop for i from 0 below (length text)
          when (char= (char text i) #\Newline) do (vector-push-extend (1+ i) v))
    v))

(defun line-of (pos)
  "1-based line and 0-based column of POS."
  (let ((lo 0) (hi (1- (length *line-starts*))))
    (loop while (< lo hi)
          do (let ((mid (ceiling (+ lo hi) 2)))
               (if (<= (aref *line-starts* mid) pos) (setf lo mid) (setf hi (1- mid)))))
    (values (1+ lo) (- pos (aref *line-starts* lo)))))

(defun note (fmt &rest args)
  (pushnew (apply #'format nil fmt args) *notes* :test #'string=))

(defun peek (pos) (if (< pos *len*) (char *text* pos) nil))

(defun skip-block-comment (pos)
  "POS is just after #|. Block comments nest."
  (let ((depth 1))
    (loop while (and (< pos *len*) (> depth 0))
          do (cond ((and (eql (peek pos) #\|) (eql (peek (1+ pos)) #\#)) (decf depth) (incf pos 2))
                   ((and (eql (peek pos) #\#) (eql (peek (1+ pos)) #\|)) (incf depth) (incf pos 2))
                   (t (incf pos))))
    pos))

(defun skip-ws (pos)
  (loop
    (let ((c (peek pos)))
      (cond ((null c) (return pos))
            ((whitespacep c) (incf pos))
            ((char= c #\;) (loop while (and (< pos *len*) (char/= (char *text* pos) #\Newline))
                                 do (incf pos)))
            ((and (char= c #\#) (eql (peek (1+ pos)) #\|)) (setf pos (skip-block-comment (+ pos 2))))
            (t (return pos))))))

(defun scan-token (pos)
  "End position of the token at POS. An unclosed | or a trailing backslash stops at the end of the text."
  (loop
    (let ((c (peek pos)))
      (cond ((or (null c) (terminatingp c)) (return pos))
            ((char= c #\\) (setf pos (min (+ pos 2) *len*)))
            ((char= c #\|)
             (incf pos)
             (loop for d = (peek pos)
                   while (and d (char/= d #\|))
                   do (setf pos (min (+ pos (if (char= d #\\) 2 1)) *len*)))
             (when (peek pos) (incf pos)))
            (t (incf pos))))))

(defun scan-string (pos)
  "POS is just after the opening quote."
  (loop for c = (peek pos)
        while (and c (char/= c #\"))
        do (incf pos (if (char= c #\\) 2 1)))
  (min *len* (1+ pos)))

(defun preview-at (pos &optional (limit *len*))
  (let* ((end (min limit (or (position #\Newline *text* :start pos) *len*)))
         (s (string-trim '(#\Space #\Tab #\Return) (subseq *text* pos end))))
    (if (> (length s) 60) (concatenate 'string (subseq s 0 57) "...") s)))

(defun read-object (pos parent)
  "Skip one object starting at or after POS. Returns (values END STATUS) where
STATUS is :OBJECT, :CLOSE (a closing paren is next) or :EOF."
  (setf pos (skip-ws pos))
  (let ((c (peek pos)))
    (cond ((null c) (values pos :eof))
          ((char= c #\)) (values pos :close))
          ((char= c #\() (values (scan-list (1+ pos) parent pos) :object))
          ((char= c #\") (values (scan-string (1+ pos)) :object))
          ((member c '(#\' #\`)) (read-prefixed (1+ pos) parent))
          ((char= c #\,) (read-prefixed (if (member (peek (1+ pos)) '(#\@ #\.)) (+ pos 2) (1+ pos))
                                        parent))
          ((char= c #\#) (read-dispatch pos parent))
          (t (values (scan-token pos) :object)))))

(defun read-prefixed (pos parent)
  (multiple-value-bind (end status) (read-object pos parent)
    (values end (if (eq status :object) :object status))))

(defun read-dispatch (start parent)
  "START is the position of #. Dispatch on the character after any numeric argument. #+ and #- become sites. An unknown macro is assumed to read one object."
  (let ((pos (1+ start)))
    (loop while (and (peek pos) (digit-char-p (peek pos))) do (incf pos))
    (let ((sub (peek pos)))
      (cond ((null sub) (values pos :object))
            ((member sub '(#\+ #\-)) (read-conditional start (1+ pos) (if (char= sub #\+) :plus :minus) parent))
            ((char= sub #\\) (values (scan-token (+ pos 2)) :object))
            ((char= sub #\() (values (scan-list (1+ pos) parent start) :object))
            ((char= sub #\|) (values (skip-block-comment (1+ pos)) :object))
            ((char= sub #\#) (values (1+ pos) :object))  ; #1#
            ((member sub '(#\: #\* #\b #\B #\o #\O #\x #\X #\r #\R))
             (values (scan-token (1+ pos)) :object))
            ((member sub '(#\' #\. #\, #\= #\c #\C #\a #\A #\s #\S #\p #\P))
             (when (char= sub #\.) (note "uses read-time evaluation (#.)"))
             (read-prefixed (1+ pos) parent))
            ((whitespacep sub) (values pos :object))
            (t
             ;; A reader macro we don't know (cl-interpol's #?, named-readtables...).
             ;; Best guess: it consumes the next object.
             (note "unknown dispatch macro #~a; assumed it reads one object" sub)
             (read-prefixed (1+ pos) parent))))))

(defun read-conditional (hash-pos fx-start kind parent)
  "HASH-POS is the # of a #+ or #-. Record a site when *recording* is true, then scan the guarded form under that site."
  (let* ((fx-begin (skip-ws fx-start))
         (fx-end (let ((*recording* nil)) (read-object fx-begin nil)))
         (raw (subseq *text* fx-begin fx-end))
         (expr (parse-feature-expression raw))
         (site nil))
    (when *recording*
      (multiple-value-bind (line col) (line-of hash-pos)
        (setf site (make-site :file *file* :line line :column col :kind kind :expr expr
                              :raw raw :parent parent
                              :comment-p (comment-idiom-p kind expr)))
        (push site *sites*)))
    ;; The guarded form. Sites inside it are nested under this one.
    (let ((form-start (skip-ws fx-end)))
      (multiple-value-bind (end status) (read-object fx-end (or site parent))
        (when site
          (if (eq status :object)
              (setf (site-preview site) (preview-at form-start end)
                    (site-end-line site) (line-of (max form-start (1- end))))
              (setf (site-preview site) "<guards nothing>")))
        (values end :object)))))

(defun token-symbol-name (text)
  "Symbol name of a token, dropping a package prefix."
  (let ((colon (position #\: text :from-end t)))
    (if colon (subseq text (1+ colon)) text)))

(defun features-place-p (text)
  (string-equal (token-symbol-name text) "*features*"))

(defun scan-list (pos parent open-pos)
  "POS is just after an opening paren. Returns the position after the closing paren."
  (let ((pending-if-feature nil)
        (index 0)
        (head nil)
        (kw nil))
    (loop
      (let ((elt-start (skip-ws pos)))
        (multiple-value-bind (end status) (read-object pos parent)
          (case status
            (:close
             (when pending-if-feature
               (setf (site-end-line pending-if-feature) (line-of end)))
             (return (1+ end)))
            (:eof
             (note "unterminated list starting on line ~a" (line-of open-pos))
             (return end))
            (t
             (when (and *recording* (< index 3) (< elt-start end))
               (let ((tok (subseq *text* elt-start end)))
                 (cond ((zerop index)
                        (let ((name (token-symbol-name tok)))
                          (when (or (string-equal name "push") (string-equal name "pushnew"))
                            (setf head name))))
                       ((and (= index 1) head (plusp (length tok)) (char= (char tok 0) #\:))
                        (setf kw (intern (string-upcase (subseq tok 1)) :keyword)))
                       ((and (= index 2) head kw (features-place-p tok))
                        (push kw *pushed-features*)))))
             (incf index)
             (when (and *asd-p* *recording*
                        (< elt-start end)
                        (string-equal (subseq *text* elt-start end) ":if-feature"))
               ;; ASDF component guard: (:file "foo" :if-feature :sbcl)
               (let* ((fx-begin (skip-ws end))
                      (fx-end (let ((*recording* nil)) (read-object fx-begin nil)))
                      (raw (subseq *text* fx-begin fx-end))
                      (expr (parse-feature-expression raw)))
                 (multiple-value-bind (line col) (line-of elt-start)
                   (setf pending-if-feature
                         (make-site :file *file* :line line :column col :kind :if-feature
                                    :expr expr :raw raw :parent parent
                                    :preview (preview-at open-pos)))
                   (push pending-if-feature *sites*))
                 (setf end fx-end)))
             (setf pos end))))))))

(defun find-pushed-features (text)
  "Features this code pushes onto *FEATURES* itself, e.g. (pushnew :foo *features*).
A push written inside a comment or a string does not count."
  (fr-pushed-features (scan-text text "t.lisp")))

(defun external-format-for (kind)
  #+clisp (ext:make-encoding :charset (ecase kind
                                        (:utf-8 charset:utf-8)
                                        (:latin-1 charset:iso-8859-1)))
  #-clisp kind)

(defun read-file-text (path)
  (flet ((slurp (format)
           (with-open-file (in path :external-format format)
             (with-output-to-string (out)
               (let ((buf (make-string 65536)))
                 (loop for n = (read-sequence buf in)
                       while (plusp n) do (write-string buf out :end n)))))))
    (handler-case (slurp (external-format-for :utf-8))
      (error () (slurp (external-format-for :latin-1))))))

(defun scan-text (text name &key asd)
  "Scan TEXT. Returns a FILE-RESULT."
  (let* ((*text* text) (*len* (length text)) (*file* name)
         (*line-starts* (compute-line-starts text))
         (*sites* '()) (*notes* '()) (*pushed-features* '())
         (*asd-p* asd) (*recording* t)
         (pos (if (and (> *len* 1) (string= "#!" text :end2 2))
                  (or (position #\Newline text) *len*)
                  0)))
    (loop
      (multiple-value-bind (end status) (read-object pos nil)
        (case status
          (:eof (return))
          (:close (note "stray closing paren on line ~a" (line-of end)) (setf pos (1+ end)))
          (t (setf pos (max end (1+ pos)))))))
    (make-file-result :name name :sites (nreverse *sites*)
                      :pushed-features (remove-duplicates (nreverse *pushed-features*))
                      :notes (nreverse *notes*))))

(defun scan-file (path &optional (name (namestring path)))
  "Scan PATH. A file whose type is asd is also scanned for :if-feature."
  (scan-text (read-file-text path) name
             :asd (string-equal (pathname-type path) "asd")))

;;; ------------------------------------------------------------------
;;; Profiles

(defun read-profile (path)
  (with-open-file (in path)
    (let* ((*read-eval* nil)
           (*package* (find-package :keyword))
           (plist (read in)))
      (make-profile :name (getf plist :name)
                    :source (getf plist :source)
                    :features (mapcar (lambda (f) (intern (string f) :keyword))
                                      (getf plist :features))))))

(defun profile-files (dir)
  "Captured profiles in DIR, not the handwritten ones under DIR/approximate/."
  (directory (merge-pathnames "*.sexp" dir)))

(defun load-profiles (dir &optional only)
  "Load *.sexp profiles in DIR.
With no name list, keep a profile only when :source has at least 13 characters
and the first 13 are string-equal to \"captured from\".
With a name list, also load DIR/approximate/*.sexp and require every requested name.
A missing name is an error."
  (let* ((extra (when only
                  (directory (merge-pathnames "approximate/*.sexp" dir))))
         (profiles (sort (mapcar #'read-profile (append (profile-files dir) extra))
                         #'string< :key #'profile-name)))
    (if only
        (let* ((selected (remove-if-not
                          (lambda (p) (member (profile-name p) only :test #'string-equal))
                          profiles))
               (missing (remove-if
                         (lambda (name)
                           (find name selected :key #'profile-name :test #'string-equal))
                         only)))
          (when missing
            (error "No profiles named ~{~a~^, ~} in ~a" missing dir))
          selected)
        (remove-if-not (lambda (p)
                         (let ((src (string (profile-source p))))
                           (and (>= (length src) 13)
                                (string-equal src "captured from" :end1 13))))
                       profiles))))

;;; Real feature names in some Lisp. A near miss against one of them is not a typo.
(defparameter *known-features*
  '(:allegro :franz-inc :lispworks :lispworks6 :lispworks7 :lispworks8 :clisp :cmu :cmucl :cmu20
    :scl :mcl :openmcl :ccl :clozure :clozure-common-lisp :ecl :abcl :armedbear :java :mkcl :clasp
    :mezzano :genera :lispm :symbolics :corman :cormanlisp :gcl :sbcl :xcl :mocl :sicl :cltl2
    :ansi-cl :common-lisp :x3j13 :draft-ansi-cl-2 :ieee-floating-point :lucid :excl :poplog
    :linux :darwin :macos :macosx :apple :windows :win32 :win64 :mswindows :unix :bsd :freebsd
    :openbsd :netbsd :dragonfly :sunos :solaris :android :ios :haiku :hpux :aix :irix :cygwin
    :mingw32 :mingw64 :msvc :posix :os-windows :os-unix :os-macosx :mach :hurd
    :x86 :x86-64 :x86_64 :amd64 :i386 :i486 :i586 :i686 :pentium3 :pentium4 :arm :arm64 :aarch64
    :armv6 :armv7 :ppc :ppc64 :powerpc :sparc :sparc64 :riscv :riscv64 :mips :mips64 :loongarch64
    :alpha :hppa :s390 :s390x :64-bit :32-bit :little-endian :big-endian :x8664-target
    :x8632-target :ppc-target :ppc32-target :ppc64-target :arm-target :arm64-target
    :64-bit-target :32-bit-target :64bit :32bit :x86-64-target
    :asdf :asdf2 :asdf3 :asdf3.1 :asdf3.2 :asdf3.3 :asdf-unicode :uiop :quicklisp :swank :slynk
    :sb-thread :sb-unicode :sb-package-locks :sb-ldb :sb-doc :sb-futex :sb-core-compression
    :sb-safepoint :sb-dynamic-core :sb-xc-host :sb-xc :sb-eval :sb-fasteval :gencgc :cheneygc
    :mark-region-gc :elf :mach-o :os-provides-dlopen :sb-dlopen :thread-support :threads
    :threaded :unicode :package-local-nicknames :os-thread :sb-thread-futex :long-float
    :short-float :double-float :ffi :dffi :uffi :cffi :cffi-features :dlopen :clos :mop
    :gray-streams :clim :mcclim :ccl-1.10 :ccl-1.11 :ccl-1.12 :ccl-1.13 :sb-unicode :ecl-bytecmp
    :relative-package-names :ios-target :darwin-target :linux-target :windows-target
    :freebsd-target :solaris-target :android-target :darwinx86-target :darwinx8664-target
    :linuxx86-target :linuxx8664-target :win64-target :win32-target :ics :fiveam :parachute))

(defun normalize-name (k)
  (remove-if (lambda (c) (member c '(#\- #\_ #\.))) (string-downcase (symbol-name k))))

(defun edit-distance (a b)
  (let* ((la (length a)) (lb (length b))
         (prev (make-array (1+ lb))) (cur (make-array (1+ lb))) (prev2 (make-array (1+ lb))))
    (dotimes (j (1+ lb)) (setf (aref prev j) j))
    (dotimes (i la (aref prev lb))
      (setf (aref cur 0) (1+ i))
      (dotimes (j lb)
        (setf (aref cur (1+ j))
              (min (1+ (aref prev (1+ j))) (1+ (aref cur j))
                   (+ (aref prev j) (if (char-equal (char a i) (char b j)) 0 1))))
        ;; Count a swap of two adjacent letters as one edit (linxu -> linux).
        (when (and (> i 0) (> j 0)
                   (char-equal (char a i) (char b (1- j)))
                   (char-equal (char a (1- i)) (char b j)))
          (setf (aref cur (1+ j)) (min (aref cur (1+ j)) (1+ (aref prev2 (1- j)))))))
      (replace prev2 prev)
      (rotatef prev cur))))

(defun near-miss (feature candidates)
  "The feature FEATURE was probably meant to be, or NIL. Deliberately conservative:
same name modulo - _ . or one edit away, but never a prefix/suffix relation
(lispworks4 is not a typo of lispworks) and never a digit change (32-bit vs 64-bit)."
  (let ((name (symbol-name feature)) (n (normalize-name feature)))
    (dolist (c candidates nil)
      (unless (eq c feature)
        (let ((cname (symbol-name c)))
          (cond ((string= n (normalize-name c)) (return c))
                ((and (>= (length name) 5)
                      (= 1 (edit-distance name cname))
                      (not (search cname name)) (not (search name cname))
                      (notany #'digit-char-p (set-exclusive-or (coerce name 'list) (coerce cname 'list))))
                 (return c))))))))

(defparameter *implementation-names*
  '("LISPWORKS" "CCL" "CLOZURE" "OPENMCL" "ALLEGRO" "EXCL" "ACL" "SBCL" "ECL" "ABCL" "CLISP"
    "CMU" "CMUCL" "MCL" "SCL" "GENERA" "MKCL" "CLASP" "CORMAN" "CORMANLISP" "GCL" "JAVA" "ASDF"))

(defun version-feature-of (feature)
  "If FEATURE looks like a versioned implementation feature (lispworks4.1, ccl-5.2,
lispworks-64bit, java-1.8), the implementation name; otherwise NIL."
  (let ((name (symbol-name feature)))
    (dolist (impl *implementation-names* nil)
      (let ((l (length impl)))
        (when (and (> (length name) l) (string= impl name :end2 l))
          (let* ((rest (string-left-trim "-._" (subseq name l))))
            (when (and (plusp (length rest)) (digit-char-p (char rest 0)))
              (return impl))))))))

;;; ------------------------------------------------------------------
;;; Analysis

;;; At most one group from each of these lists can be present in one image.
;;; Used to spot guards no Common Lisp could ever satisfy, like #+ccl inside #+sbcl.
(defparameter *exclusive-groups*
  '(((:sbcl) (:ccl :openmcl :clozure) (:ecl) (:abcl :armedbear) (:clisp) (:cmu :cmucl) (:scl)
     (:allegro :franz-inc) (:lispworks) (:mcl :digitool) (:genera) (:mkcl) (:clasp)
     (:cormanlisp :corman) (:gcl) (:xcl) (:mocl) (:mezzano))
    ((:linux) (:darwin) (:win32 :windows :mswindows :win64) (:freebsd) (:openbsd) (:netbsd)
     (:sunos :solaris))))

(defun guard-status (site profile)
  "Whether SITE's guard lets its form be read under PROFILE (ignoring parents)."
  (guard-status-in site (profile-features profile) (profile-maybe profile)))

(defun guard-status-in (site features &optional maybe)
  (let ((v (eval-feature-expression (site-expr site) features maybe)))
    (if (eq (site-kind site) :minus)
        (case v (:true :false) (:false :true) (t :unknown))
        v)))

(defun read-status (site profile)
  "Whether SITE's guarded form is read under PROFILE, taking enclosing guards into account."
  (let ((own (guard-status site profile))
        (outer (if (site-parent site) (read-status (site-parent site) profile) :true)))
    (cond ((or (eq own :false) (eq outer :false)) :false)
          ((or (eq own :unknown) (eq outer :unknown)) :unknown)
          (t :true))))

(defun site-chain (site)
  (loop for s = site then (site-parent s) while s collect s))

(defun chain-atoms (site)
  (remove-duplicates (loop for s in (site-chain site) append (fx-atoms (site-expr s)))))

(defun consistent-features-p (features)
  (every (lambda (groups)
           (<= (count-if (lambda (g) (intersection g features)) groups) 1))
         *exclusive-groups*))

(defun chain-satisfiable (site)
  "T when some feature set reads SITE's form, NIL when none can, :UNKNOWN when the guard is not static or the search is wider than 16 names."
  (let ((chain (site-chain site)) (atoms (chain-atoms site)))
    (cond ((some (lambda (s) (and (consp (site-expr s)) (member (first (site-expr s)) '(:dynamic :bad))))
                 chain)
           :unknown)
          ((> (length atoms) 16) :unknown)
          (t (dotimes (mask (expt 2 (length atoms)) nil)
               (let ((features (loop for a in atoms for i from 0 when (logbitp i mask) collect a)))
                 (when (and (consistent-features-p features)
                            (every (lambda (s) (eq (guard-status-in s features) :true)) chain))
                   (return t))))))))

(defun inside-comment-p (site)
  (loop for p = (site-parent site) then (site-parent p)
        while p thereis (site-comment-p p)))

(defun analyze (results profiles extra-known)
  "Features the scanned code pushes itself become 'maybe' in every profile that
doesn't already have them: the push may be conditional or run after the read."
  (let* ((sites (loop for r in results append (fr-sites r)))
         (pushed (remove-duplicates (loop for r in results append (fr-pushed-features r))))
         (profiles (mapcar (lambda (p)
                             (make-profile :name (profile-name p) :source (profile-source p)
                                           :features (profile-features p)
                                           :maybe (set-difference pushed (profile-features p))))
                           profiles))
         (matrix-features (remove-duplicates (loop for p in profiles
                                                    append (append (profile-features p) (profile-maybe p)))))
         (known (remove-duplicates (append matrix-features *known-features* pushed extra-known)))
         (live (remove-if (lambda (s) (or (site-comment-p s) (inside-comment-p s))) sites))
         (contradictions '()) (matrix-dead '()) (untested (make-hash-table))
         (outside (make-hash-table)) (typos '()) (dynamic '()))
    (dolist (s live)
      (when (and (consp (site-expr s)) (member (first (site-expr s)) '(:dynamic :bad)))
        (push s dynamic))
      (dolist (a (fx-atoms (site-expr s)))
        (unless (member a matrix-features)
          (push s (gethash a outside))))
      ;; Classify the outermost never-read site of each dead region.
      (when (and (every (lambda (p) (eq (read-status s p) :false)) profiles)
                 (or (null (site-parent s))
                     (notevery (lambda (p) (eq (read-status (site-parent s) p) :false)) profiles)))
        (let ((missing (remove-if (lambda (a) (member a matrix-features)) (chain-atoms s))))
          (cond ((null (chain-satisfiable s)) (push s contradictions))
                ((null missing) (push s matrix-dead))
                (t (dolist (m missing) (push s (gethash m untested))))))))
    (loop for k being the hash-keys of outside
          do (let ((guess (and (not (member k known)) (not (version-feature-of k))
                               (near-miss k known))))
               (when guess (push (list k guess (reverse (gethash k outside))) typos))))
    (list :profiles profiles :sites sites :live live
          :contradictions (nreverse contradictions) :matrix-dead (nreverse matrix-dead)
          :untested untested :outside outside
          :typos (sort typos #'string< :key (lambda (x) (symbol-name (first x))))
          :comment-sites (remove-if-not #'site-comment-p sites)
          :dynamic (nreverse dynamic)
          :pushed pushed :known known :matrix-features matrix-features)))

;;; ------------------------------------------------------------------
;;; Reporting

(defun site-guard-string (s)
  (ecase (site-kind s)
    (:plus (format nil "#+~a" (fx-to-string (site-expr s))))
    (:minus (format nil "#-~a" (fx-to-string (site-expr s))))
    (:if-feature (format nil ":if-feature ~a" (fx-to-string (site-expr s))))))

(defun loc (s)
  (if (and (site-end-line s) (> (site-end-line s) (site-line s)))
      (format nil "~a:~a-~a" (site-file s) (site-line s) (site-end-line s))
      (format nil "~a:~a" (site-file s) (site-line s))))

(defun status-char (v) (case v (:true "+") (:false ".") (t "?")))

(defun has-empty-or-p (expr)
  (and (consp expr)
       (or (equal expr '(:or))
           (and (member (first expr) '(:and :or :not)) (some #'has-empty-or-p (rest expr))))))

(defun print-sites (sites stream &key (limit 15) (preview t) chain)
  (dolist (s (subseq sites 0 (min limit (length sites))))
    (format stream "  ~a  ~a~:[~;   (contains (or), so probably disabled on purpose)~]~%"
            (loc s) (site-guard-string s)
            (and chain (some (lambda (x) (has-empty-or-p (site-expr x))) (site-chain s))))
    (when chain
      (dolist (p (rest (site-chain s)))
        (format stream "      inside ~a at line ~a~%" (site-guard-string p) (site-line p))))
    (when (and preview (site-preview s))
      (format stream "      ~a~%" (site-preview s))))
  (when (> (length sites) limit)
    (format stream "  ... and ~a more (use --all, --json, or --json-full)~%" (- (length sites) limit))))

(defun hash-to-ranked-list (table)
  "((key . sites) ...) sorted by number of sites, most first."
  (sort (loop for k being the hash-keys of table using (hash-value v)
              collect (cons k (remove-duplicates (reverse v))))
        (lambda (a b) (or (> (length (cdr a)) (length (cdr b)))
                          (and (= (length (cdr a)) (length (cdr b)))
                               (string< (symbol-name (car a)) (symbol-name (car b))))))))

(defun files-count (sites) (length (remove-duplicates (mapcar #'site-file sites) :test #'string=)))

(defun report-text (results profiles analysis &key all (stream *standard-output*))
  "Write the text report to STREAM."
  (declare (ignore profiles))
  (let* ((profiles (getf analysis :profiles))
         (live (getf analysis :live))
         (contradictions (getf analysis :contradictions))
         (matrix-dead (getf analysis :matrix-dead))
         (typos (getf analysis :typos)))
    (format stream "skiptrace: ~a contradiction~:p, ~a typo~:p~%"
            (length contradictions) (length typos))
    (format stream "skiptrace: ~a file~:p, ~a guarded form~:p (~a commented out with #+(or)/#+nil/#+ignore)~%~%"
            (length results) (length (getf analysis :sites)) (length (getf analysis :comment-sites)))
    (format stream "Implementations:~%")
    (loop for p in profiles for i from 1
          do (format stream "  [~a] ~a~@[  -- ~a~]~%" i (profile-name p) (profile-source p)))

    (when all
      (format stream "~%== Every guarded form ==   + reads the form, . skips the form, ? not a static feature test~%")
      (dolist (s live)
        (format stream "  ~{~a~^ ~}  ~a  ~a~%"
                (mapcar (lambda (p) (status-char (read-status s p))) profiles)
                (loc s) (site-guard-string s))))

    (format stream "~%== Impossible guard chains — enclosing conditions cannot all be true (~a) ==~%" (length contradictions))
    (if contradictions
        (print-sites contradictions stream :chain t :limit (if all 100000 15))
        (format stream "  none~%"))

    (format stream "~%== Likely typos in feature names (~a) ==~%" (length typos))
    (if typos
        (dolist (x typos)
          (destructuring-bind (k guess where) x
            (format stream "  :~(~a~) -- did you mean :~(~a~)?~%" k guess)
            (print-sites where stream :preview nil :limit 5)))
        (format stream "  none~%"))

    (format stream "~%== Never read by selected profiles — all referenced features are known, but none of the selected profiles reaches these forms (~a) ==~%"
            (length matrix-dead))
    (if matrix-dead
        (print-sites matrix-dead stream :limit (if all 100000 10))
        (format stream "  none~%"))

    (let ((untested (remove-if (lambda (u) (assoc (car u) typos))
                               (hash-to-ranked-list (getf analysis :untested)))))
      (format stream "~%== Requires features absent from the selected profiles ==~%")
      (if untested
          (dolist (u untested)
            (format stream "  :~(~30a~) ~4d form~:p in ~d file~:p~%" (car u) (length (cdr u)) (files-count (cdr u))))
          (format stream "  none~%")))

    (let* ((outside (hash-to-ranked-list (getf analysis :outside)))
           (known (getf analysis :known))
           (other (remove-if (lambda (o) (or (member (car o) known) (assoc (car o) typos))) outside)))
      (when other
        (format stream "~%== Other feature names not present in the selected profiles (~a) ==~%" (length other))
        (dolist (o other)
          (format stream "  :~(~30a~) ~4d site~:p~@[   (version feature of ~(~a~))~]~%"
                  (car o) (length (cdr o)) (version-feature-of (car o))))))

    (let ((risky (remove-if-not (lambda (s) (and (eq (site-kind s) :plus) (member (site-expr s) '(:nil :ignore))))
                                (getf analysis :comment-sites))))
      (when risky
        (format stream "~%== #+nil / #+ignore used to comment out code (~a) ==~%" (length risky))
        (format stream "  These break if anything ever pushes :nil or :ignore onto *features*. #+(or) can't.~%")
        (print-sites risky stream :preview nil :limit 5)))

    (let ((dyn (getf analysis :dynamic)))
      (when dyn
        (format stream "~%== Guards decided at read time by #. or nonstandard syntax (~a) ==~%" (length dyn))
        (let ((by-file (make-hash-table :test #'equal)))
          (dolist (s dyn) (incf (gethash (site-file s) by-file 0)))
          (loop for f in (sort (loop for k being the hash-keys of by-file collect k) #'string<)
                do (format stream "  ~a: ~a~%" f (gethash f by-file))))))

    (let ((pushed (getf analysis :pushed)))
      (when pushed
        (format stream "~%Features this code pushes onto *features* itself (treated as unknown, not as present):~%  ~{:~(~a~)~^ ~}~%" pushed)))

    (format stream "~%== Per implementation ==~%")
    (dolist (p profiles)
      (let ((n (count :true live :key (lambda (s) (read-status s p)))))
        (format stream "  ~30a reads ~4d of ~d guarded forms~%" (profile-name p) n (length live))))

    (let ((notes (loop for r in results
                       append (mapcar (lambda (n) (format nil "~a: ~a" (fr-name r) n)) (fr-notes r)))))
      (when notes
        (format stream "~%Scanner notes:~%")
        (dolist (n notes) (format stream "  ~a~%" n))))))

(defun json-string (s stream)
  (write-char #\" stream)
  (loop for c across (princ-to-string s)
        do (case c
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Tab (write-string "\\t" stream))
             (t (if (< (char-code c) 32)
                    (format stream "\\u~4,'0x" (char-code c))
                    (write-char c stream)))))
  (write-char #\" stream))

(defun report-json (profiles analysis &key (stream *standard-output*))
  "Write the JSON report to STREAM."
  (declare (ignore profiles))
  (let ((profiles (getf analysis :profiles))
        (contradictions (getf analysis :contradictions))
        (matrix-dead (getf analysis :matrix-dead)))
    (format stream "{~%  \"profiles\": [")
    (loop for (p . more) on profiles do (json-string (profile-name p) stream) (when more (write-string ", " stream)))
    (format stream "],~%  \"sites\": [~%")
    (loop for (s . more) on (getf analysis :live)
          do (format stream "    {\"file\": ") (json-string (site-file s) stream)
             (format stream ", \"line\": ~a, \"end_line\": ~a, \"guard\": " (site-line s) (or (site-end-line s) (site-line s)))
             (json-string (site-guard-string s) stream)
             (format stream ", \"read_by\": {")
             (loop for (p . pm) on profiles
                   do (json-string (profile-name p) stream)
                      (format stream ": ~a" (case (read-status s p) (:true "true") (:false "false") (t "null")))
                      (when pm (write-string ", " stream)))
             (format stream "}, \"finding\": ~a}~:[~;,~]~%"
                     (cond ((member s contradictions) "\"contradiction\"")
                           ((member s matrix-dead) "\"never-read-in-matrix\"")
                           (t "null"))
                     more))
    (format stream "  ],~%  \"likely_typos\": [")
    (loop for ((k guess where) . more) on (getf analysis :typos)
          do (format stream "~%    {\"feature\": ") (json-string (string-downcase (symbol-name k)) stream)
             (format stream ", \"suggestion\": ") (json-string (string-downcase (symbol-name guess)) stream)
             (format stream ", \"count\": ~a}~:[~;,~]" (length where) more))
    (format stream "~%  ]~%}~%")))

(defun json-strings (items stream)
  (write-char #\[ stream)
  (loop for (item . more) on items
        do (json-string item stream)
           (when more (write-string ", " stream)))
  (write-char #\] stream))

(defun parent-guard-strings (site)
  (mapcar #'site-guard-string (rest (site-chain site))))

(defun site-intentional-p (site)
  (some (lambda (x) (has-empty-or-p (site-expr x))) (site-chain site)))

(defun write-full-finding (stream finding more)
  "One finding object. COUNT and FILES are omitted unless COUNT is a number."
  (format stream "    {")
  (json-string "kind" stream) (write-string ": " stream) (json-string (getf finding :kind) stream)
  (write-string ", " stream)
  (json-string "severity" stream) (write-string ": " stream) (json-string (getf finding :severity) stream)
  (write-string ", " stream)
  (json-string "intentional" stream) (write-string ": " stream)
  (write-string (if (getf finding :intentional) "true" "false") stream)
  (write-string ", " stream)
  (json-string "file" stream) (write-string ": " stream)
  (if (getf finding :file) (json-string (getf finding :file) stream) (write-string "null" stream))
  (format stream ", \"line\": ~a, \"end_line\": ~a, " (or (getf finding :line) 0) (or (getf finding :end-line) 0))
  (json-string "guard" stream) (write-string ": " stream)
  (if (getf finding :guard) (json-string (getf finding :guard) stream) (write-string "null" stream))
  (write-string ", " stream)
  (json-string "feature" stream) (write-string ": " stream)
  (if (getf finding :feature) (json-string (getf finding :feature) stream) (write-string "null" stream))
  (write-string ", " stream)
  (json-string "suggestion" stream) (write-string ": " stream)
  (if (getf finding :suggestion) (json-string (getf finding :suggestion) stream) (write-string "null" stream))
  (write-string ", " stream)
  (json-string "parent_guards" stream) (write-string ": " stream)
  (json-strings (or (getf finding :parent-guards) '()) stream)
  (write-string ", " stream)
  (json-string "preview" stream) (write-string ": " stream)
  (if (getf finding :preview) (json-string (getf finding :preview) stream) (write-string "null" stream))
  (when (numberp (getf finding :count))
    (format stream ", \"count\": ~a, \"files\": ~a" (getf finding :count) (or (getf finding :files) 0)))
  (format stream "}~:[~;,~]~%" more))

(defun full-findings (analysis)
  "Contradictions, typos with locations, never-read forms, risky comment idioms,
dynamic guards, and one summary row per absent or other feature name."
  (let ((findings '())
        (contradictions (getf analysis :contradictions))
        (typos (getf analysis :typos))
        (matrix-dead (getf analysis :matrix-dead)))
    (dolist (s contradictions)
      (push (list :kind "contradiction"
                  :severity (if (site-intentional-p s) "info" "high")
                  :intentional (site-intentional-p s)
                  :file (site-file s) :line (site-line s)
                  :end-line (or (site-end-line s) (site-line s))
                  :guard (site-guard-string s)
                  :feature nil :suggestion nil
                  :parent-guards (parent-guard-strings s)
                  :preview (site-preview s))
            findings))
    (dolist (group typos)
      (destructuring-bind (k guess where) group
        (let ((feature (string-downcase (symbol-name k)))
              (suggestion (string-downcase (symbol-name guess))))
          (dolist (s where)
            (push (list :kind "likely-typo" :severity "review" :intentional nil
                        :file (site-file s) :line (site-line s)
                        :end-line (or (site-end-line s) (site-line s))
                        :guard (site-guard-string s)
                        :feature feature :suggestion suggestion
                        :parent-guards (parent-guard-strings s)
                        :preview (site-preview s))
                  findings)))))
    (dolist (s matrix-dead)
      (push (list :kind "never-read-in-matrix" :severity "info" :intentional nil
                  :file (site-file s) :line (site-line s)
                  :end-line (or (site-end-line s) (site-line s))
                  :guard (site-guard-string s)
                  :feature nil :suggestion nil
                  :parent-guards (parent-guard-strings s)
                  :preview (site-preview s))
            findings))
    (dolist (s (remove-if-not (lambda (site)
                                (and (eq (site-kind site) :plus)
                                     (member (site-expr site) '(:nil :ignore))))
                              (getf analysis :comment-sites)))
      (push (list :kind "comment-idiom" :severity "info" :intentional nil
                  :file (site-file s) :line (site-line s)
                  :end-line (or (site-end-line s) (site-line s))
                  :guard (site-guard-string s)
                  :feature nil :suggestion nil
                  :parent-guards (parent-guard-strings s)
                  :preview (site-preview s))
            findings))
    (dolist (s (getf analysis :dynamic))
      (push (list :kind "dynamic" :severity "info" :intentional nil
                  :file (site-file s) :line (site-line s)
                  :end-line (or (site-end-line s) (site-line s))
                  :guard (site-guard-string s)
                  :feature nil :suggestion nil
                  :parent-guards (parent-guard-strings s)
                  :preview (site-preview s))
            findings))
    (let ((untested (remove-if (lambda (u) (assoc (car u) typos))
                               (hash-to-ranked-list (getf analysis :untested))))
          (known (getf analysis :known))
          (outside (hash-to-ranked-list (getf analysis :outside))))
      (dolist (u untested)
        (let* ((sites (cdr u))
               (ex (first sites)))
          (push (list :kind "absent-feature" :severity "info" :intentional nil
                      :file (and ex (site-file ex)) :line (and ex (site-line ex))
                      :end-line (and ex (or (site-end-line ex) (site-line ex)))
                      :guard (and ex (site-guard-string ex))
                      :feature (string-downcase (symbol-name (car u)))
                      :suggestion nil
                      :parent-guards (and ex (parent-guard-strings ex))
                      :preview (and ex (site-preview ex))
                      :count (length sites) :files (files-count sites))
                findings)))
      (dolist (o (remove-if (lambda (item) (or (member (car item) known) (assoc (car item) typos))) outside))
        (let* ((sites (cdr o))
               (ex (first sites))
               (version (version-feature-of (car o))))
          (push (list :kind "other-feature" :severity "info" :intentional nil
                      :file (and ex (site-file ex)) :line (and ex (site-line ex))
                      :end-line (and ex (or (site-end-line ex) (site-line ex)))
                      :guard (and ex (site-guard-string ex))
                      :feature (string-downcase (symbol-name (car o)))
                      :suggestion (and version (string-downcase version))
                      :parent-guards (and ex (parent-guard-strings ex))
                      :preview (and ex (site-preview ex))
                      :count (length sites) :files (files-count sites))
                findings))))
    (nreverse findings)))

(defun report-json-full (results profiles analysis &key (stream *standard-output*))
  "Findings with locations. Does not change the --json keys."
  (declare (ignore profiles))
  (let* ((profiles (getf analysis :profiles))
         (risky (remove-if-not (lambda (s) (and (eq (site-kind s) :plus) (member (site-expr s) '(:nil :ignore))))
                               (getf analysis :comment-sites)))
         (findings (full-findings analysis))
         (notes (loop for r in results
                      append (mapcar (lambda (n) (format nil "~a: ~a" (fr-name r) n)) (fr-notes r)))))
    (format stream "{~%  \"profiles\": [")
    (loop for (p . more) on profiles do (json-string (profile-name p) stream) (when more (write-string ", " stream)))
    (format stream "],~%  \"counts\": {~%    \"files\": ~a,~%    \"guarded_forms\": ~a,~%    \"contradictions\": ~a,~%    \"likely_typos\": ~a,~%    \"never_read\": ~a,~%    \"comment_idioms\": ~a,~%    \"dynamic\": ~a~%  },~%  \"findings\": [~%"
            (length results)
            (length (getf analysis :sites))
            (length (getf analysis :contradictions))
            (length (getf analysis :typos))
            (length (getf analysis :matrix-dead))
            (length risky)
            (length (getf analysis :dynamic)))
    (loop for (f . more) on findings do (write-full-finding stream f more))
    (format stream "  ],~%  \"notes\": [")
    (loop for (n . more) on notes
          do (json-string n stream) (when more (write-string ", " stream)))
    (format stream "]~%}~%")))

;;; ------------------------------------------------------------------
;;; Entry point

(defparameter *lisp-types* '("lisp" "lsp" "cl" "asd"))

(defun as-directory (path)
  "PATH interpreted as a directory pathname, whether or not it has a trailing slash."
  (let ((p (pathname path)))
    (if (and (null (pathname-name p)) (null (pathname-type p)))
        p
        (make-pathname :device (pathname-device p)
                       :directory (append (or (pathname-directory p) '(:relative))
                                          (list (pathname-name p)))
                       :name nil :type nil))))

(defun directory-exists-p (dir)
  #+clisp (ignore-errors (ext:probe-directory dir))
  #-clisp (let ((p (probe-file dir)))
            (and p (null (pathname-name p)) (null (pathname-type p)))))

(defun resolve-directory (path)
  (let ((dir (as-directory path)))
    (when (directory-exists-p dir)
      (or #-clisp (probe-file dir)
          #+clisp (ignore-errors (truename dir))
          dir))))

(defun existing-source-file (path)
  "Probe PATH as a file. CLISP errors when PROBE-FILE is given a directory."
  (handler-case
      (let ((p (probe-file path)))
        (when (and p (pathname-name p)) p))
    (error () nil)))

(defun subdirectory-p (path)
  (and (null (pathname-name path))
       (null (pathname-type path))
       (pathname-directory path)))

(defun git-path-p (path)
  (member ".git" (pathname-directory path) :test #'string=))

(defun lisp-source-p (path)
  (and (pathname-name path)
       (member (pathname-type path) *lisp-types* :test #'string-equal)))

(defun subdirectory-wild (dir)
  "Wildcard pathname matching the subdirectories of DIR."
  (make-pathname :name nil :type nil
                 :directory (append (pathname-directory (pathname dir)) '(:wild))
                 :defaults dir))

(defun directory-entries (dir)
  "Files and subdirectories of DIR. ECL's DIRECTORY omits subdirectories from a
name/type wildcard, so those are listed with a directory wildcard. A failure in
either listing does not discard the other."
  (labels ((safe (thunk)
             (handler-case (funcall thunk) (error () '()))))
    (append
     (safe (lambda ()
             #+clisp (directory (merge-pathnames #p"*.*" dir))
             #-clisp (directory (merge-pathnames (make-pathname :name :wild :type :wild) dir))))
     (remove-if-not #'subdirectory-p
                    (safe (lambda ()
                            #+clisp (directory (merge-pathnames #p"*/" dir))
                            #-clisp (directory (subdirectory-wild dir))))))))

(defun relative-display (file root)
  (let* ((f (namestring file))
         (r (namestring root))
         (r (if (and (plusp (length r))
                     (char/= (char r (1- (length r))) #\/))
                (concatenate 'string r "/")
                r)))
    (if (and (>= (length f) (length r)) (string= f r :end1 (length r)))
        (subseq f (length r))
        (enough-namestring file root))))

(defun walk-lisp-files (root)
  (let ((seen (make-hash-table :test #'equal)))
    (labels ((recurse (dir)
               (let ((key (namestring dir)))
                 (unless (or (gethash key seen) (git-path-p dir))
                   (setf (gethash key seen) t)
                   (loop for entry in (directory-entries dir)
                         nconc (cond ((subdirectory-p entry) (recurse entry))
                                     ((and (lisp-source-p entry) (not (git-path-p entry)))
                                      (list (cons entry (relative-display entry root))))))))))
      (recurse root))))

(defun collect-files (path)
  "PATH may be a file or directory. Returns (pathname . display-name) pairs."
  (let ((file (existing-source-file path))
        (dir (resolve-directory path)))
    (cond (file (list (cons file (namestring path))))
          (dir (sort (walk-lisp-files dir) #'string< :key #'cdr))
          (t (error "No such file or directory: ~a" path)))))

(defun system-profile-dir ()
  "profiles/ beside the skiptrace system, once ASDF knows the system.
The command-line launcher passes that directory itself and does not need this."
  (unless (find-package :asdf)
    (ignore-errors (require :asdf)))
  (let ((asdf (find-package :asdf)))
    (when asdf
      (let ((fn (find-symbol "SYSTEM-RELATIVE-PATHNAME" asdf)))
        (when (fboundp fn)
          (let ((dir (ignore-errors (funcall fn :skiptrace "profiles/"))))
            (when (and dir (directory-exists-p (as-directory dir)))
              (as-directory dir))))))))

(defun audit-paths (paths &key profile-dir only extra-known)
  "Scan PATHS against the profiles in PROFILE-DIR. Returns the file results, the profiles, and the analysis plist."
  (let* ((profile-dir (or profile-dir
                          (system-profile-dir)
                          (error "No profile directory. Pass --profile-dir, or load skiptrace through ASDF so profiles/ can be found beside the system.")))
         (profiles (load-profiles profile-dir only))
         (results (loop for path in paths
                        append (loop for (file . name) in (collect-files path)
                                     collect (handler-case (scan-file file name)
                                               (error (e)
                                                 (make-file-result :name name :notes (list (format nil "could not scan: ~a" e)))))))))
    (values results profiles (analyze results profiles extra-known))))

(defun split-commas (s)
  (loop with start = 0
        for comma = (position #\, s :start start)
        collect (subseq s start comma)
        while comma do (setf start (1+ comma))))

(defun usage ()
  (format t "Usage: skiptrace [options] PATH...

Reports which #+/#- forms and ASDF :if-feature components each loaded
implementation reads.

Options:
  --profiles NAME,NAME   Only use these profiles (default: all in the profile dir)
  --profile-dir DIR      Where *.sexp profiles live (default: ../profiles next to this tool)
  --known FEAT,FEAT      Extra feature names to treat as legitimate
  --all                  Print every guarded form, not only the findings
  --json                 Machine-readable summary (profiles, sites, likely_typos)
  --json-full            Findings with file, line, parent guards, and previews
  --strict               Exit 1 on contradictions or likely typos (for CI)
  -h, --help             This text
"))

(defun main (args &key default-profile-dir)
  "Parse ARGS and write the text report, JSON, or --json-full. Returns 0, 1, or 2.
When both --json and --json-full are set, --json-full wins. --json keys stay unchanged."
  (let ((paths '()) (only nil) (profile-dir default-profile-dir) (extra '())
        (all nil) (json nil) (json-full nil) (strict nil))
    (loop while args
          do (let ((a (pop args)))
               (cond ((member a '("-h" "--help") :test #'string=) (usage) (return-from main 0))
                     ((string= a "--profiles") (setf only (split-commas (pop args))))
                     ((string= a "--profile-dir") (setf profile-dir (pathname (concatenate 'string (string-right-trim "/" (pop args)) "/"))))
                     ((string= a "--known")
                      (setf extra (mapcar (lambda (s) (intern (string-upcase (string-left-trim ":" s)) :keyword))
                                          (split-commas (pop args)))))
                     ((string= a "--all") (setf all t))
                     ((string= a "--json") (setf json t))
                     ((string= a "--json-full") (setf json-full t))
                     ((string= a "--strict") (setf strict t))
                     ((string= a "--") nil)
                     (t (push a paths)))))
    (when (null paths) (usage) (return-from main 2))
    (multiple-value-bind (results profiles analysis)
        (audit-paths (nreverse paths) :profile-dir profile-dir :only only :extra-known extra)
      (cond (json-full (report-json-full results profiles analysis))
            (json (report-json profiles analysis))
            (t (report-text results profiles analysis :all all)))
      (if (and strict (or (getf analysis :contradictions) (getf analysis :typos)))
          1 0))))
