# Web Crawler

A web crawler that crawls a website, extracts content as Markdown, and saves each page to disk.

## Quick Start

```bash
# Set your target URL and run
./crawler --url https://example.com

# Check the results
ls output/
```

For verbose output:

```bash
DEBUG=1 ./crawler --url https://example.com
```

## Configuration

The crawler reads runtime options from environment variables. The only required input is `--url`; everything else has sensible defaults.

| Variable | Default | Effect |
|---|---|---|
| `DEBUG` | unset | When `1`, logs every queued URL and every URL skipped by a filter rule. |
| `MAX_URL_LENGTH` | `0` (unlimited) | URLs longer than this (after fragment/trailing-slash cleanup) are skipped. Catches session-encoded URLs and crawler traps. Set to `0` (the default — also used when the var is unset or non-numeric) to disable the length check entirely. |
| `SKIP_WORDS_IN_URL` | unset | Comma-separated list of stopwords. A URL is skipped when any of its path/query tokens exactly matches one of these words. Token boundaries are non-alphanumeric characters, so `en` matches `/en/` but not `/engineering/`. |

Example:

```bash
DEBUG=1 \
MAX_URL_LENGTH=300 \
SKIP_WORDS_IN_URL=en,veranstaltungen,login \
./crawler --url https://example.com
```

In addition to these env vars, `FilterUrl Handler` (in `links.aro`) hard-codes two filters that aren't configurable: a non-HTML extension blocklist (images, archives, fonts, …) and a repeated-path-segment guard (URLs like `/x/x/x/…` are usually broken templates).

## How It Works

The crawler is fully event-driven. No feature set calls another directly -- they communicate exclusively through events and a repository observer:

```
Application-Start
       |
       v
  QueueUrl event ───> QueueUrl Handler
                           |
                      Store into crawled-repository
                           |
                      crawled-repository Observer
                           |
                      CrawlPage event ───> CrawlPage Handler
                                                |
                                    ┌───────────┴───────────┐
                                    v                       v
                              SavePage event          ExtractLinks event
                                    |                       |
                              SavePage Handler        ExtractLinks Handler
                              (write .md file)              |
                                                   parallel for each link:
                                                            |
                                                   NormalizeUrl Handler
                                                            |
                                                   FilterUrl Handler
                                                            |
                                                   QueueUrl event ──┐
                                                                    |
                                               (loops back, repo   |
                                                deduplicates)  <───┘
```

URL deduplication happens automatically: the repository ignores stores with duplicate IDs (each URL is hashed to a deterministic ID). The observer only fires for new entries.

## Project Structure

```
Crawler/
├── main.aro        # Entry point: reads --url parameter, creates output dir, emits first QueueUrl
├── crawler.aro     # CrawlPage Handler: fetches HTML, extracts Markdown, emits SavePage + ExtractLinks
├── links.aro       # Link pipeline: ExtractLinks, NormalizeUrl, FilterUrl, QueueUrl, repository Observer
├── storage.aro     # SavePage Handler: writes Markdown files to output/
├── openapi.yaml    # Event schemas (CrawlPageEvent, ExtractLinksEvent, etc.)
└── output/         # Crawled pages as .md files (created at runtime)
```

## Output Format

Each crawled page is saved as a Markdown file named by the SHA-256 hash of its URL:

```markdown
# Page Title

**Source:** https://example.com/page

---

Content with headings, links, lists, and formatting preserved...
```

