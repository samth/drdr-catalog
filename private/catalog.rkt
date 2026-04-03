#lang racket/base
(require racket/file
         racket/list
         racket/string
         "fetch.rkt")

(provide create-catalog)

;; Pin a source URL to a specific commit hash so that installing from the
;; catalog checks out exactly that commit, not HEAD.
;;
;; git:// and https:// URLs: append #<checksum> fragment
;;   git://github.com/racket/2d?path=2d
;;   → git://github.com/racket/2d?path=2d#4b70b2dc...
;;
;; github:// URLs: replace the branch component with the checksum
;;   github://github.com/greghendershott/aws/master
;;   → github://github.com/greghendershott/aws/4b70b2dc...
(define (pin-source source checksum)
  (cond
    [(string-prefix? source "github://")
     ;; github://host/user/repo/branch[/path...]
     ;; Replace the branch (4th component) with the checksum
     (define without-scheme (substring source (string-length "github://")))
     (define parts (string-split without-scheme "/"))
     ;; parts = (host user repo branch [path...])
     (cond
       [(>= (length parts) 4)
        (define host (list-ref parts 0))
        (define user (list-ref parts 1))
        (define repo (list-ref parts 2))
        ;; Everything after the branch is path
        (define path-parts (list-tail parts 4))
        (define new-parts (list* host user repo checksum path-parts))
        (define result (string-append "github://" (string-join new-parts "/")))
        ;; Preserve trailing slash if original had one
        (if (string-suffix? source "/")
            (if (string-suffix? result "/") result (string-append result "/"))
            result)]
       [else
        ;; Malformed github:// URL, fall back to appending fragment
        (string-append source "#" checksum)])]
    [else
     ;; git://, https://, or other: append #checksum fragment
     ;; Strip any existing fragment first
     (define base
       (let ([idx (for/last ([i (in-range (string-length source))]
                             #:when (char=? (string-ref source i) #\#))
                    i)])
         (if idx (substring source 0 idx) source)))
     (string-append base "#" checksum)]))

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
    (define source (pin-source (package-entry-source entry)
                               (package-entry-checksum entry)))
    (define ht (hash 'source source
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
