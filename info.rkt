#lang info

(define collection "drdr-catalog")
(define deps '("base" "net-lib"))
(define build-deps '("rackunit-lib"))
(define raco-commands
  '(("drdr-catalog" drdr-catalog/main "create a package catalog from a DrDr build" #f)))
