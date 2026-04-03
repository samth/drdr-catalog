#lang racket/base
(require racket/file
         racket/string
         racket/system
         "fetch.rkt")

(provide find-revision-for-sha
         sha->revision-number?)

;; Is the argument a plausible SHA prefix (hex string, >= 7 chars)
;; but not a pure decimal number (which would be a revision number)?
(define (sha->revision-number? s)
  (and (regexp-match? #px"^[0-9a-f]{7,40}$" s)
       (not (regexp-match? #px"^[0-9]+$" s))))

;; Run a git command in the given repo directory, return trimmed stdout or #f
(define (git-in-repo repo-path . args)
  (define out (open-output-string))
  (define err (open-output-string))
  (define ok?
    (parameterize ([current-directory repo-path]
                   [current-output-port out]
                   [current-error-port err])
      (apply system* (find-executable-path "git") args)))
  (and ok? (string-trim (get-output-string out))))

;; Get the commit timestamp for a SHA
(define (git-commit-timestamp repo-path sha)
  (define result (git-in-repo repo-path "show" "-s" "--format=%ct" sha))
  (and result (string->number result)))

;; Check if sha-a is an ancestor of sha-b
(define (git-is-ancestor? repo-path sha-a sha-b)
  (parameterize ([current-directory repo-path]
                 [current-output-port (open-output-string)]
                 [current-error-port (open-output-string)])
    (system* (find-executable-path "git")
             "merge-base" "--is-ancestor" sha-a sha-b)))

;; Cache directory for SHA-to-revision mappings
(define (cache-dir)
  (define d (build-path (find-system-path 'home-dir) ".cache" "drdr-catalog"))
  (make-directory* d)
  d)

(define (cache-file)
  (build-path (cache-dir) "sha-to-rev.rktd"))

(define (load-cache)
  (with-handlers ([exn:fail? (lambda (_) (hash))])
    (file->value (cache-file))))

(define (save-cache ht)
  (write-to-file ht (cache-file) #:exists 'replace))

;; Known anchor point: revision 62000 has timestamp 1667112830
(define ANCHOR-REV 62000)
(define ANCHOR-TS 1667112830)

;; Fetch the latest revision number from the DrDr main page
(define (fetch-latest-revision server)
  (define html (fetch-url (format "~a/" server)))
  (define m (regexp-match #px"href=\"(\\d+)/\"" html))
  (and m (string->number (cadr m))))

;; Estimate a revision number from a timestamp using linear interpolation
(define (estimate-revision target-ts latest-rev latest-ts)
  (define seconds-per-rev
    (/ (- latest-ts ANCHOR-TS) (- latest-rev ANCHOR-REV)))
  (define est (+ ANCHOR-REV
                 (inexact->exact
                  (round (/ (- target-ts ANCHOR-TS) seconds-per-rev)))))
  (max ANCHOR-REV (min latest-rev est)))

;; Find the DrDr revision that tested a given commit SHA.
;; Returns the revision number, or #f if not found.
(define (find-revision-for-sha sha repo-path server)
  ;; Check cache first
  (define cache (load-cache))
  (define cached (hash-ref cache sha #f))
  (cond
    [cached
     (eprintf "drdr-catalog: using cached revision ~a for ~a\n" cached sha)
     cached]
    [else
     ;; Get commit timestamp from git
     (define target-ts (git-commit-timestamp repo-path sha))
     (unless target-ts
       (error 'find-revision-for-sha
              "could not get timestamp for commit ~a in ~a" sha repo-path))

     ;; Get latest revision info
     (define latest-rev (fetch-latest-revision server))
     (define latest-ts (fetch-revision-timestamp latest-rev server))

     ;; Start with an estimate, then binary search
     (define est (estimate-revision target-ts latest-rev latest-ts))
     (eprintf "drdr-catalog: estimated revision ~a for timestamp ~a\n" est target-ts)

     (define result
       (let loop ([lo ANCHOR-REV] [hi latest-rev] [next est])
         (cond
           [(> lo hi) #f]
           [else
            (define mid (max lo (min hi next)))
            (eprintf "drdr-catalog: checking revision ~a (range ~a..~a)\n" mid lo hi)
            (define end-sha (fetch-revision-sha mid server))
            (cond
              [(not end-sha)
               ;; Revision page has no commit info, try next
               (loop (add1 mid) hi (add1 mid))]
              [(or (equal? end-sha sha)
                   (string-prefix? end-sha sha)
                   (string-prefix? sha end-sha))
               ;; Exact match (or prefix match for short SHAs)
               mid]
              [(git-is-ancestor? repo-path sha end-sha)
               ;; Target is at or before this revision.
               ;; Check if it's after the previous revision.
               (define prev-sha (fetch-revision-sha (sub1 mid) server))
               (cond
                 [(not prev-sha)
                  (loop lo (sub1 mid) (quotient (+ lo (sub1 mid)) 2))]
                 [(git-is-ancestor? repo-path sha prev-sha)
                  ;; Target is before prev too, search lower
                  (loop lo (sub1 mid) (quotient (+ lo (sub1 mid)) 2))]
                 [else
                  ;; Target is between prev and current — this is the revision
                  mid])]
              [else
               ;; Target is after this revision, search higher
               (loop (add1 mid) hi (quotient (+ (add1 mid) hi) 2))])])))

     ;; Cache and return
     (when result
       (save-cache (hash-set cache sha result)))
     result]))
