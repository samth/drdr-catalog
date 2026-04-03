#lang racket/base
(require racket/file
         racket/list
         "fetch.rkt")

(provide create-catalog)

;; Create a directory-based Racket package catalog from package entries.
;; The catalog follows the protocol documented in catalog-protocol.scrbl:
;;   pkgs      — a read-able list of package name strings
;;   pkg/<name> — a read-able hash with 'source and 'checksum keys
(define (create-catalog entries output-dir)
  (define pkg-dir (build-path output-dir "pkg"))
  (make-directory* pkg-dir)

  ;; Write individual pkg/<name> files
  (for ([entry (in-list entries)])
    (define name (package-entry-name entry))
    (define ht (hash 'source (package-entry-source entry)
                     'checksum (package-entry-checksum entry)))
    (call-with-output-file (build-path pkg-dir name)
      #:exists 'replace
      (lambda (out)
        (write ht out)
        (newline out))))

  ;; Write pkgs file
  (define names (sort (map package-entry-name entries) string<?))
  (call-with-output-file (build-path output-dir "pkgs")
    #:exists 'replace
    (lambda (out)
      (write names out)
      (newline out))))
