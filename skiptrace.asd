(defsystem "skiptrace"
  :description "Reports which #+/#- guarded forms each Lisp implementation never reads."
  :license "MIT"
  :version "0.1.0"
  :components ((:module "src" :components ((:file "skiptrace"))))
  :in-order-to ((test-op (test-op "skiptrace/tests"))))

(defsystem "skiptrace/tests"
  :depends-on ("skiptrace")
  :components ((:module "tests" :components ((:file "tests"))))
  :perform (test-op (o c) (symbol-call :skiptrace-tests :run-tests)))
