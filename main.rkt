#lang racket/base
(require racket/cmdline
         racket/format
         racket/string
         racket/path
         "private/fetch.rkt"
         "private/catalog.rkt"
         "private/revision-lookup.rkt")

(define DEFAULT-SERVER "http://hurin.soic.indiana.edu")

(define current-server (make-parameter DEFAULT-SERVER))
(define current-variant (make-parameter "cs"))
(define current-git-repo (make-parameter #f))

(module+ main
  (define-values (rev-or-sha output-dir)
    (command-line
     #:program "raco drdr-catalog"
     #:once-each
     [("--server") server "DrDr server URL" (current-server server)]
     [("--variant") variant "Build variant: cs or bc (default: cs)" (current-variant variant)]
     [("--git-repo") repo "Path to local racket/racket clone (required for SHA lookup)"
      (current-git-repo repo)]
     #:args (revision-or-sha output-dir)
     (values revision-or-sha output-dir)))

  (define server (current-server))
  (define variant (current-variant))

  ;; Determine revision number
  (define rev
    (cond
      [(string->number rev-or-sha)
       => (lambda (n) n)]
      [(sha->revision-number? rev-or-sha)
       (unless (current-git-repo)
         (error 'drdr-catalog
                "~a looks like a commit SHA; --git-repo is required for SHA lookup"
                rev-or-sha))
       (eprintf "Looking up DrDr revision for commit ~a...\n" rev-or-sha)
       (define found (find-revision-for-sha rev-or-sha (current-git-repo) server))
       (unless found
         (error 'drdr-catalog "could not find a DrDr revision for commit ~a" rev-or-sha))
       (eprintf "Found revision ~a\n" found)
       found]
      [else
       (error 'drdr-catalog
              "~a is not a revision number or a commit SHA" rev-or-sha)]))

  ;; Fetch the commit SHA for this revision
  (eprintf "Fetching revision ~a info...\n" rev)
  (define commit-sha (fetch-revision-sha rev server))
  (unless commit-sha
    (error 'drdr-catalog "could not find commit SHA for revision ~a" rev))

  ;; Fetch and parse pkg-show
  (eprintf "Fetching package list...\n")
  (define entries (fetch-pkg-show rev server variant))
  (when (null? entries)
    (error 'drdr-catalog "no packages found for revision ~a variant ~a" rev variant))

  ;; Create catalog
  (eprintf "Creating catalog with ~a packages...\n" (length entries))
  (create-catalog entries output-dir)

  ;; Print summary
  (printf "Racket commit: ~a\n" commit-sha)
  (printf "DrDr revision: ~a\n" rev)
  (printf "Variant: ~a\n" variant)
  (printf "Catalog: ~a/ (~a packages)\n" (path->string (simple-form-path output-dir)) (length entries))
  (define catalog-url (format "file://~a" (path->string (simple-form-path output-dir))))
  (printf "\nTo reproduce this build:\n")
  (printf "  git clone https://github.com/racket/racket && cd racket\n")
  (printf "  git checkout ~a\n" commit-sha)
  (printf "  make ~a SRC_CATALOG=~s\n"
          (if (equal? variant "cs") "cs" "bc")
          catalog-url))

;; Package names that DrDr explicitly installs (from pkgs.rktd).
;; Everything else in the catalog is an auto-installed dependency.
(define explicitly-installed-names
  '("job-queue-lib" "job-queue-doc" "job-queue"
    "drdr"
    "remote-shell-lib" "remote-shell-doc" "remote-shell"
    "plt-web-lib" "plt-web-doc" "plt-web"
    "distro-build-client" "distro-build-server"
    "distro-build-doc" "distro-build-lib" "distro-build"
    "sha" "http" "aws" "bcrypt"
    "shrubbery-lib" "s3-sync"
    "plt-service-monitor" "infrastructure-userdb"
    "pkg-push" "pkg-index" "pkg-build"))
