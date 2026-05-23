# API surface

The crawler exposes **no HTTP API**. It is a one-shot CLI process driven by `--url`. The only contract it does maintain is an internal event-payload schema in `../openapi.yaml` — every handler validates its input against a named component there.

This file documents both surfaces.

## CLI

```text
crawler --url <seed-url>
```

| Arg | Required | Notes |
|---|---|---|
| `--url` | yes | Seed URL. Read in `main.aro` via `Extract the <start-url> from the <parameter: url>`. Same value is also used as the base domain — only links containing this string survive the same-domain guard in `FilterUrl Handler`. |

There are no subcommands, no `--help` flag wired up beyond ARO's default, and no exit-code conventions beyond standard `0` on clean shutdown.

## Environment variables

See [`./setup.md`](./setup.md#configuration). Briefly: `DEBUG`, `MAX_URL_LENGTH`, `SKIP_WORDS_IN_URL`.

## Internal event schemas

`openapi.yaml` is reused as a payload-schema registry — `paths: {}` is empty because the crawler has no HTTP routes. Each event below is referenced from a handler via `Extract the <event-data: SomeEvent> from the <event>`, which fails the crawl if the payload doesn't match.

| Event | Schema (in `openapi.yaml`) | Emitted by | Consumed by |
|---|---|---|---|
| `QueueUrl` | `QueueUrlEvent` | `main.aro` (seed); `FilterUrl Handler` (loop) | `QueueUrl Handler` |
| `CrawlPage` | `CrawlPageEvent` | `crawled-repository Observer` | `CrawlPage Handler` |
| `SavePage` | `SavePageEvent` | `CrawlPage Handler` | `SavePage Handler` |
| `ExtractLinks` | `ExtractLinksEvent` | `CrawlPage Handler` | `ExtractLinks Handler` |
| `NormalizeUrl` | `NormalizeUrlEvent` | `ExtractLinks Handler` | `NormalizeUrl Handler` |
| `FilterUrl` | `FilterUrlEvent` | `NormalizeUrl Handler` | `FilterUrl Handler` |
| `CrawlRequest` (repository record) | `CrawlRequest` | `QueueUrl Handler` (Store) | observer machinery |

### Adding a new event

1. Add the schema to `openapi.yaml` under `components.schemas` first.
2. In the handler that consumes it, write `Extract the <event-data: YourNewEvent> from the <event>.`.
3. In any emitter, write `Emit a <YourNewEvent: event> with { ... }.`.

The order matters — referencing an unknown schema name from a handler will fail `aro check`.

## Output format

Each crawled page becomes one Markdown file at `./output/<sha256(url)>.md`:

```markdown
# <page title>

**Source:** <url>

---

<markdown body from ParseHtml>
```

The hash that names the file is the same `id` used as the repository key, so `output/<hash>.md` and the queued entry correspond 1:1.

## Versioning

There is no API versioning scheme in this repository. `openapi.yaml` reports `info.version: 1.0.0` but that value is not surfaced anywhere at runtime. Container images are tagged `<ref-slug>-<short-sha>` and additionally `:latest` on the default branch and `:<git-tag>` on tag pushes. Native binary releases are versioned by the git tag (`aro-crawler-<tag>-linux-amd64.tar.gz`).

<!-- TODO: confirm whether the wiki's API Versioning policy (URL path versioning, deprecation headers) applies to event-only services. The crawler has no HTTP routes, so URL-path versioning is N/A by construction. -->
