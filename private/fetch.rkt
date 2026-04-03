#lang racket/base
(require racket/match
         racket/string
         racket/port
         racket/list
         net/url)

(provide (struct-out package-entry)
         fetch-url
         fetch-pkg-show
         fetch-revision-sha
         fetch-revision-timestamp
         parse-pkg-show-text)

(struct package-entry (name checksum source) #:transparent)

;; Fetch a URL and return the body as a string
(define (fetch-url url-str)
  (define u (string->url url-str))
  (define port (get-pure-port u #:redirections 5))
  (begin0 (port->string port)
    (close-input-port port)))

;; Unescape HTML entities
(define (html-unescape s)
  (define s1 (string-replace s "&lt;" "<"))
  (define s2 (string-replace s1 "&gt;" ">"))
  (define s3 (string-replace s2 "&amp;" "&"))
  (define s4 (string-replace s3 "&quot;" "\""))
  s4)

;; Extract all <pre class="stdout">...</pre> blocks from HTML
(define (extract-stdout-blocks html)
  (define rx #rx"<pre class=\"stdout\">(.*?)</pre>")
  (for/list ([m (in-list (regexp-match* rx html #:match-select cadr))])
    (html-unescape (if (bytes? m) (bytes->string/utf-8 m) m))))

;; Parse a single line of pkg-show output into a package-entry or #f
(define (parse-pkg-show-line line)
  (define trimmed (string-trim line))
  (cond
    ;; (catalog "name" "url") format
    [(regexp-match
      #px"^([^ *]+)\\*?\\s+([0-9a-f]{40})\\s+\\(catalog \"([^\"]+)\" \"([^\"]+)\"\\)"
      trimmed)
     => (lambda (m)
          (package-entry (list-ref m 1) (list-ref m 2) (list-ref m 4)))]
    ;; (url "url") format
    [(regexp-match
      #px"^([^ *]+)\\*?\\s+([0-9a-f]{40})\\s+\\(url \"([^\"]+)\"\\)"
      trimmed)
     => (lambda (m)
          (package-entry (list-ref m 1) (list-ref m 2) (list-ref m 3)))]
    ;; static-link or header lines — skip
    [else #f]))

;; Parse pkg-show text (list of lines) into package entries
(define (parse-pkg-show-text lines)
  (filter-map parse-pkg-show-line lines))

;; Fetch and parse pkg-show for a given revision
;; Returns (listof package-entry)
(define (fetch-pkg-show rev server [variant "cs"])
  (define url-str
    (format "~a/~a/~a/pkg-show" server rev
            (if (equal? variant "cs") "cs" "")))
  (define html (fetch-url url-str))
  (define lines (extract-stdout-blocks html))
  (parse-pkg-show-text lines))

;; Fetch the racket/racket commit SHA for a revision
;; Returns string or #f
(define (fetch-revision-sha rev server)
  (define url-str (format "~a/~a/" server rev))
  (define html (fetch-url url-str))
  (define m (regexp-match #px"github\\.com/racket/racket/commit/([0-9a-f]{40})" html))
  (and m (cadr m)))

;; Fetch the build start timestamp for a revision
;; Returns integer (unix timestamp) or #f
(define (fetch-revision-timestamp rev server)
  (define url-str (format "~a/~a/" server rev))
  (define html (fetch-url url-str))
  (define m (regexp-match #rx"data-timestamp=\"([0-9]+)\"" html))
  (and m (string->number (cadr m))))
