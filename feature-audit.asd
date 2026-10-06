(defsystem "feature-audit"
  :description "Reports which #+/#- guarded forms each Lisp implementation never reads."
  :license "MIT"
  :version "0.1.0"
  :components ((:module "src" :components ((:file "feature-audit"))))
  :in-order-to ((test-op (test-op "feature-audit/tests"))))

(defsystem "feature-audit/tests"
  :depends-on ("feature-audit")
  :components ((:module "tests" :components ((:file "tests"))))
  :perform (test-op (o c) (symbol-call :feature-audit-tests :run-tests)))
