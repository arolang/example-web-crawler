# ARO Web Crawler

> A real-world web crawler built with ARO - demonstrating event-driven architecture, parallel processing, and the power of declarative programming.

[![ARO Language](https://img.shields.io/badge/ARO-Language-6366f1)](https://github.com/arolang/aro)
[![Demo Application](https://img.shields.io/badge/type-demo-22c55e)](https://github.com/arolang/aro)

---

## What is this?

This is a **fully functional web crawler** written in [ARO](https://github.com/arolang/aro), a domain-specific language for expressing business logic as Action-Result-Object statements. It's designed to show you what ARO can do in a real-world scenario - not just "Hello World", but actual working software.

Point it at any website, and it will crawl pages, extract content, and save everything locally. Along the way, you'll see how ARO handles events, concurrency, state management, and more.

---

## Quick Start

```bash
# Clone this repository
git clone https://github.com/arolang/example-web-crawler.git
cd example-web-crawler

# Set your target URL
export CRAWL_URL="https://example.com"

# Run the crawler
aro run .

# Check the results
ls output/
```

That's it. No build step, no configuration files, no boilerplate.

---

## What You'll Learn

This demo showcases key ARO features you'll use in your own applications:

| Feature | Where to look | What it does |
|---------|---------------|--------------|
| **Event-Driven Architecture** | All files | Feature sets communicate through events, not direct calls |
| **Parallel Processing** | `links.aro` | `parallel for each` processes multiple URLs concurrently |
| **Set Operations** | `crawler.aro` | `difference` and `union` for URL deduplication |
| **Pattern Matching** | `links.aro` | `match` with regex patterns classifies URL types |
| **HTML Parsing** | `crawler.aro`, `links.aro` | `<ParseHtml>` extracts links and content |
| **Repository Persistence** | `crawler.aro` | `<Store>` and `<Retrieve>` manage crawled URL state |
| **Long-Running Apps** | `main.aro` | `<Keepalive>` keeps the event loop alive |

---

## How It Works

```
Application Start
       |
       v
  Emit CrawlPage ──────────────────────────────────────┐
       |                                               |
       v                                               |
  CrawlPage Handler                                    |
       |                                               |
       ├── Check if already crawled (set difference)   |
       ├── Fetch HTML from URL                         |
       ├── Extract content with <ParseHtml>            |
       ├── Save to file ──> SavePage Handler           |
       └── Extract links ──> ExtractLinks Handler      |
                                   |                   |
                                   v                   |
                            For each link:             |
                                   |                   |
                            NormalizeUrl Handler       |
                                   |                   |
                            FilterUrl Handler          |
                                   |                   |
                            QueueUrl Handler ──────────┘
                            (emits CrawlPage if new)
```

The crawler forms a natural event loop - each crawled page discovers new links, which trigger new crawl events, until all pages are visited.

---

## Project Structure

```
example-web-crawler/
├── main.aro      # Application entry point, initialization
├── crawler.aro   # Page fetching, content extraction
├── links.aro     # Link extraction, URL normalization, filtering
├── storage.aro   # File saving operations
└── output/       # Crawled content (created at runtime)
```

**~200 lines of ARO code** for a complete, parallel, deduplicating web crawler.

---

## Try It Yourself

Once you've run the basic demo, try these experiments:

**Crawl a different site:**
```bash
export CRAWL_URL="https://your-favorite-site.com"
aro run .
```

**Modify the domain filter** in `links.aro` to crawl a different domain:
```aro
match <url> {
    case /^https?:\/\/your-domain\.com/ {
        <Emit> a <QueueUrl: event> with { url: <url>, base: <base-domain> }.
    }
}
```

**Add new URL patterns** to skip or include in `links.aro`

**Extract different content** - modify the `<ParseHtml>` calls in `crawler.aro`

---

## Help Improve ARO

This demo is part of the ARO language project. If you:

- **Find a bug** in the language or runtime
- **Have an idea** for a new feature
- **Want to improve** the syntax or semantics
- **Need clarification** on how something works

Please open an issue on the main ARO repository:

**[github.com/arolang/aro/issues](https://github.com/arolang/aro/issues)**

Your feedback shapes the language. Every issue helps make ARO better for everyone.

---

## Learn More

| Resource | Description |
|----------|-------------|
| [ARO Repository](https://github.com/arolang/aro) | Source code, issues, and releases |
| [Language Guide (PDF)](https://github.com/arolang/aro/releases/latest/download/ARO-Language-Guide.pdf) | Complete language reference |
| [Wiki](https://github.com/arolang/aro/wiki) | Tutorials and guides |
| [Discussions](https://github.com/arolang/aro/discussions) | Ask questions, share ideas |

---

## License

MIT - Use this code however you like. Build something cool with ARO.
