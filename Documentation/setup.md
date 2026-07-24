# Local development setup

## Prerequisites

| Tool | Version | Source |
|---|---|---|
| ARO toolchain | `0.11.2` matches the CI build image | `ghcr.io/arolang/aro-buildsystem:0.11.2` — install locally from <https://arolang.github.io/aro/> |
| Docker (optional) | Any recent version supporting multi-stage builds | For `docker compose up` path |
| `curl`, `tar`, `sha256sum` | System defaults | Only needed if you replicate the `package_linux_amd64` CI step locally |

No language runtime besides ARO is required. The compiled binary is statically linkable enough to run on the `aro-runtime` base image without extra system libraries.

## Clone and validate

```bash
git clone <this-repo>
cd Crawler
aro check .
```

`aro check .` is the entire test stage in CI — there is no unit test suite. If it passes, the sources are syntactically and semantically valid against `openapi.yaml`.

## Run from source

```bash
aro run . --url https://example.com
```

Verbose logging:

```bash
DEBUG=1 aro run . --url https://example.com
```

## Build a native binary

```bash
aro build . --release -o crawler
./crawler --url https://example.com
```

The release binary lands in the working directory. CI uploads the same artifact (tarred + sha256'd) to the GitLab generic package registry on tag pushes.

## Run via Docker

```bash
docker compose up
# or, directly:
docker build -t aro-crawler .
docker run -v $(pwd)/output:/output aro-crawler --url https://example.com
```

The container runs as the non-root `aro` user with `/output` as its working directory; mount your host output path to `/output`.

## Configuration

All runtime tuning lives in environment variables. Defaults are sensible — only `--url` is required.

| Variable | Default | Effect |
|---|---|---|
| `DEBUG` | unset | When `1`, logs every queued URL and every URL skipped by a filter rule (non-HTML extension, repeated path segments, overlong, stopword, cross-domain). |
| `MAX_URL_LENGTH` | `0` (unlimited) | URLs longer than this (after fragment/trailing-slash cleanup) are skipped. Set to `0` (also the default — used when the var is unset, empty, or non-numeric) to disable the length check entirely. |
| `SKIP_WORDS_IN_URL` | unset | Comma-separated list of stopwords. A URL is skipped when any of its path/query tokens exactly matches one of these words. Tokenizer splits on `[^a-zA-Z0-9]+`, so `en` matches `/en/` but not `/engineering/`. |

Example with all knobs:

```bash
DEBUG=1 \
MAX_URL_LENGTH=300 \
SKIP_WORDS_IN_URL=en,veranstaltungen,login \
./crawler --url https://www.example.com/
```

## Editor / IDE

The repository ships an `.idea/` directory (JetBrains). ARO has an LSP available via `aro lsp` for editors that support custom language servers. There is no enforced formatter or linter beyond `aro check`.
