(defsystem "skiptrace"
  :description "Reports which #+/#- guarded forms each Lisp implementation never reads."
  :author "Michael A. Kuykendall <michaelallenkuykendall@gmail.com>"
  :license "MIT"
  :homepage "https://github.com/Michael-A-Kuykendall/skiptrace"
  :bug-tracker "https://github.com/Michael-A-Kuykendall/skiptrace/issues"
  :version "0.1.0"
  :components ((:module "src" :components ((:file "skiptrace"))))
  :in-order-to ((test-op (test-op "skiptrace/tests"))))

(defsystem "skiptrace/tests"
  :depends-on ("skiptrace")
  :components ((:module "tests" :components ((:file "tests"))))
  :perform (test-op (o c)
             (unless (symbol-call :skiptrace-tests :run-tests)
               (error "skiptrace tests failed."))))
