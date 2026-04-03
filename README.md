# drdr-catalog

Create Racket package catalogs from [DrDr](https://drdr.racket-lang.org) builds for reproducibility.

DrDr records the exact package versions installed for each build via `raco pkg show -al --full-checksum`. This tool turns that data into a standard Racket package catalog with every source URL pinned to the exact commit hash, so you can reproduce an old build by passing the catalog to `make`.

## Installation

```
raco pkg install https://github.com/samth/drdr-catalog.git
```

## Usage

### By revision number

```
raco drdr-catalog 65000 /tmp/catalog-65000
```

### By commit SHA (requires a local racket/racket clone)

```
raco drdr-catalog --git-repo ~/racket 9b93ea8d /tmp/catalog
```

### Reproducing a build

```
raco drdr-catalog 65000 /tmp/catalog-65000
git clone https://github.com/racket/racket && cd racket
git checkout 9b93ea8d3d8762dc4774cebc07dc11bfbe10972a
make cs SRC_CATALOG="file:///tmp/catalog-65000"
```

The generated catalog is a standard Racket directory catalog. You can inspect it with:

```
raco pkg catalog-show --catalog file:///tmp/catalog-65000 rackunit-lib
```

## Options

```
raco drdr-catalog [options] <revision-or-sha> <output-dir>

  --git-repo <path>    Path to local racket/racket clone (required for SHA lookup)
  --variant cs|bc      Build variant (default: cs)
  --server <url>       DrDr server URL
```

## How it works

For a given DrDr revision, the tool:

1. Fetches the `pkg-show` log from the DrDr web interface
2. Parses each package entry to extract the name, checksum, and source URL
3. Pins each source URL to its exact commit (appending `#<checksum>` to git URLs, replacing the branch in `github://` URLs)
4. Writes a directory catalog with `pkgs` and `pkg/<name>` files per the [Racket catalog protocol](https://docs.racket-lang.org/pkg/catalog-protocol.html)

Packages with `static-link` sources (from the racket/racket repo itself) are excluded since they're determined by the checkout.

## Coverage

All DrDr revisions from 62000 to present (~10,500 revisions, Oct 2022 onward) use a consistent format and are supported.
