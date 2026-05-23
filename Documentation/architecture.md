# Architecture summary

The full C4-style diagrams (System Context, Container, Component, Deployment, Network, Sequence, Event Payload Relationships) live in [`../ARCHITECTURE.md`](../ARCHITECTURE.md). This page is a textual digest for readers who want the shape of the system without the diagrams.

## One-paragraph summary

The crawler is a single OS process. `main.aro` reads a seed URL from `--url`, creates `./output/`, and emits one `QueueUrl` event. From there everything is event-driven: each new URL lands in an in-memory repository keyed by `sha256(url)`, an observer fires on insert, the page is fetched and parsed once, markdown is written, and the extracted links fan out through a normalize → filter → queue pipeline that loops back into the repository. Duplicates die at the repository layer; the observer simply does not fire for an id that already exists. The program exits when the event queue drains.

## Source files

| File | Role |
|---|---|
| `main.aro` | `Application-Start` / `Application-End`. Seeds the crawl, prints the metrics table on exit. |
| `crawler.aro` | `CrawlPage Handler`. Fetches HTML, runs `ParseHtml` once, fans out to `SavePage` + `ExtractLinks`. |
| `links.aro` | The full link pipeline: `ExtractLinks` (parallel fan-out, cap 16) → `NormalizeUrl` → `FilterUrl` → `QueueUrl` → `crawled-repository Observer`. |
| `storage.aro` | `SavePage Handler`. Writes `./output/<sha256(url)>.md`. |
| `openapi.yaml` | Source of truth for event payload shapes. Every handler validates its input against a schema here. |

## Key invariants

- **No direct calls between feature sets.** Inter-handler communication is exclusively `Emit a <SomeEvent: event>` plus the repository observer. New stages should be inserted as events, not function calls.
- **Dedup is structural.** The repository's `id = sha256(url)` collides for identical URLs; the second `Store` is silently dropped. There is no explicit "have we seen this URL?" check anywhere in the code, and there should not be one.
- **HTML never leaves `CrawlPage`.** Both consumers (`SavePage` and `ExtractLinks`) receive pre-extracted derivatives (markdown, link list). An earlier version emitted the raw HTML body and the same ~500 KB string ended up retained inside every in-flight fan-out handler.
- **Parallelism is capped.** `ExtractLinks Handler` uses `parallel for each ... with <concurrency: 16>`. Without the cap, ARO defaults `concurrency` to `items.count`, which on link-heavy pages explodes the Task count.
- **URL filtering lives only in `FilterUrl Handler`.** Extension blocklist, length cap, stopword check, repeated-segment check, same-domain guard — all in one match block. Adjust there, not by sprinkling checks across handlers.

## External dependencies

| Kind | What | Where |
|---|---|---|
| Build base image | `ghcr.io/arolang/aro-buildsystem:0.9.6` | `Dockerfile` stage 1 |
| Runtime base image | `ghcr.io/arolang/aro-runtime:latest` | `Dockerfile` stage 2 |
| Target HTTP(S) sites | Arbitrary, supplied by `--url` | User-provided |
| Local filesystem | `./output/` host-side, `/output` in container | Output volume |

There is no database, no message broker, no third-party API beyond the target site itself.

## Configuration surface

Documented exhaustively in [`./setup.md`](./setup.md#configuration). Summary: `--url` is the only required CLI flag; runtime behaviour is tuned via `DEBUG`, `MAX_URL_LENGTH`, `SKIP_WORDS_IN_URL`.
