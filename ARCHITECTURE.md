# Architecture

The ARO Web Crawler is a single-binary, event-driven web crawler written in [ARO](https://arolang.github.io/aro/). It accepts a seed URL on the command line, fetches HTML over HTTP(S), converts each page to Markdown, and writes one `.md` file per page to `./output/`. There is no database, no message broker, no inbound network surface — only outbound HTTP and a local filesystem write. The whole crawl runs as one OS process; concurrency comes from ARO's in-process event-handler scheduler, capped at 16 parallel link normalizations per page.

The diagrams below are generated from facts in this repository only: the four `.aro` source files, `openapi.yaml`, `Dockerfile`, `docker-compose.yml`, and `.gitlab-ci.yml`. They are written in Mermaid because (a) the project is small enough that C4-DSL/PlantUML would be overkill, (b) GitLab renders Mermaid natively in Markdown and Wiki pages, and (c) the rest of the docs are Markdown-first.

## 1. System Context (C4 Level 1)

A single actor — the operator who runs `crawler --url ...` — directs the crawler at a target website. The crawler reads HTML from that target and writes Markdown to the local filesystem. There are no other inbound or outbound connections at runtime.

```mermaid
C4Context
    title System Context — ARO Web Crawler

    Person(operator, "Operator", "Runs the crawler from a shell or CI job, supplies the seed URL via --url and tuning via env vars (DEBUG, MAX_URL_LENGTH, SKIP_WORDS_IN_URL).")

    System(crawler, "ARO Web Crawler", "Fetches a website, converts each page to Markdown, writes one .md file per page.")

    System_Ext(target, "Target Website", "Any HTTP(S) site. Only same-domain links are followed.")
    SystemDb_Ext(output, "Output Directory", "Local filesystem path ./output/ (or /output inside the container).")

    Rel(operator, crawler, "Starts with --url, monitors via stdout/stderr")
    Rel(crawler, target, "HTTP(S) GET")
    Rel(crawler, output, "Writes <sha256(url)>.md")
```

## 2. Container Diagram (C4 Level 2)

The deployable surface is one container image (or one native binary). At runtime the only persistent boundary is the mounted output volume. The build pipeline pulls two upstream images from GitHub Container Registry but those are build/runtime base layers, not separately deployed containers.

```mermaid
C4Container
    title Container View — ARO Web Crawler

    Person(operator, "Operator")

    System_Boundary(sys, "ARO Web Crawler") {
        Container(crawler_bin, "crawler", "ARO 0.9.6 / native binary", "Single process. Reads --url, runs the full event chain, exits when the queue drains.")
        ContainerDb(repo, "crawled-repository", "In-memory ARO repository", "Hash-keyed dedup store. Observer fires only on new ids.")
    }

    System_Ext(target, "Target Website", "HTTP(S)")
    SystemDb_Ext(output, "./output/", "Local volume / bind mount")

    Rel(operator, crawler_bin, "CLI: --url <seed>; env: DEBUG, MAX_URL_LENGTH, SKIP_WORDS_IN_URL")
    Rel(crawler_bin, target, "HTTP(S) GET, parses HTML via SwiftSoup-backed ParseHtml")
    Rel(crawler_bin, repo, "Store crawl-request {id, url, base}")
    Rel(repo, crawler_bin, "Observer event with newValue")
    Rel(crawler_bin, output, "Write <sha256(url)>.md")
```

## 3. Component Diagram (C4 Level 3)

The crawler's internals are five feature sets distributed across four `.aro` files plus the implicit `crawled-repository`. Feature sets never call each other directly — communication is exclusively `Emit a <SomeEvent: event>` plus the repository observer that drives the crawl loop.

```mermaid
flowchart LR
    subgraph main_aro["main.aro"]
        AS["Application-Start\nReads --url, makes ./output/,\nemits seed QueueUrl"]
        AE["Application-End\nLogs metrics table"]
    end

    subgraph links_aro["links.aro"]
        QH["QueueUrl Handler\nHashes URL → id,\nstores crawl-request"]
        OBS["crawled-repository Observer\nFires once per new id,\nemits CrawlPage"]
        EL["ExtractLinks Handler\nparallel for each link\nwith concurrency: 16"]
        NU["NormalizeUrl Handler\nResolve absolute / root /\nrelative hrefs"]
        FU["FilterUrl Handler\nStrip fragment, drop non-HTML\next, length, stopwords, dedup-domain"]
    end

    subgraph crawler_aro["crawler.aro"]
        CP["CrawlPage Handler\nHTTP GET, ParseHtml ONCE\n(title + markdown + links)"]
    end

    subgraph storage_aro["storage.aro"]
        SP["SavePage Handler\nWrite ./output/<sha256>.md"]
    end

    REPO[("crawled-repository\n(in-memory, id-keyed)")]
    SCHEMA["openapi.yaml\nEvent payload schemas\nvalidated by Extract"]

    AS -->|"Emit QueueUrl"| QH
    QH -->|"Store"| REPO
    REPO -.->|"new id"| OBS
    OBS -->|"Emit CrawlPage"| CP
    CP -->|"Emit SavePage"| SP
    CP -->|"Emit ExtractLinks (link list, not HTML)"| EL
    EL -->|"Emit NormalizeUrl"| NU
    NU -->|"Emit FilterUrl"| FU
    FU -->|"Emit QueueUrl (loop)"| QH

    SCHEMA -.validates.- CP
    SCHEMA -.validates.- EL
    SCHEMA -.validates.- NU
    SCHEMA -.validates.- FU
    SCHEMA -.validates.- QH
    SCHEMA -.validates.- SP
```

## 4. Deployment Diagram

Two release channels are produced by `.gitlab-ci.yml`: a container image (Kaniko-built, Trivy-scanned, `crane`-pushed to the project's container registry) and, on tag pushes, a `linux-amd64` native binary uploaded to the GitLab generic package registry and attached to a GitLab Release.

```mermaid
flowchart TB
    subgraph dev["Developer workstation"]
        SRC["Source: *.aro,\nopenapi.yaml, Dockerfile"]
    end

    subgraph ci["GitLab CI (.gitlab-ci.yml)"]
        T["test:\naro check ."]
        B["build:\nKaniko → image.tar"]
        S["scan:\nTrivy CVE\nfail on MEDIUM/HIGH/CRITICAL"]
        SAST["SAST-IaC\n(template)"]
        SEC["Secret-Detection\n(template)"]
        P["publish:\ncrane push to\n$CI_REGISTRY_IMAGE"]
        PKG["package_linux_amd64:\naro build → tar.gz\n+ sha256 to package registry"]
        REL["release:\nGitLab Release with\nbinary asset links"]
    end

    subgraph reg["GitLab Container Registry"]
        IMG["aro-crawler:&lt;ref&gt;-&lt;sha&gt;\n+ :latest on default branch\n+ :&lt;tag&gt; on tag"]
    end

    subgraph pkgreg["GitLab Generic Package Registry"]
        TAR["aro-crawler-&lt;tag&gt;-linux-amd64.tar.gz\n+ .sha256"]
    end

    subgraph runtime["Runtime targets"]
        DOCKER["Docker / docker compose\nentrypoint: /usr/local/bin/crawler\nuser: aro (non-root)\nworkdir: /output\nvolume: ./output → /output"]
        BIN["Bare host\n./crawler --url ..."]
    end

    SRC --> T --> B --> S --> P
    T --> SAST
    T --> SEC
    S --> P
    P --> IMG
    SRC --> PKG --> TAR
    PKG --> REL

    IMG --> DOCKER
    TAR --> BIN
```

## 5. Network Topology

The crawler has zero inbound listeners. The only outbound network is HTTP(S) to whatever site the operator passes via `--url`. Same-domain filtering in `FilterUrl Handler` means the crawl stays within one origin per invocation. There are no service-to-service calls, no auth proxies, no service mesh.

```mermaid
flowchart LR
    OP[("Operator shell\nor CI runner")]

    subgraph host["Host / Container Network"]
        CR["crawler process\nbound to no port,\nno inbound socket"]
        FS[("/output\n(bind mount / volume)")]
    end

    subgraph internet["Public Internet"]
        DNS["DNS (system resolver)"]
        TGT["Target website\n:80 / :443"]
    end

    OP -- "exec / docker run" --> CR
    CR -- "name lookup" --> DNS
    CR -- "TCP :80/:443 → HTTP/HTTPS GET" --> TGT
    CR -- "POSIX write" --> FS

    classDef bound stroke-dasharray: 4 2
    class host bound
```

## 6. Event Sequence — One Page Through the Pipeline

The most useful operational view of this system is the sequence a single URL traverses from seed to written `.md`. Dedup short-circuits the loop at `QueueUrl Handler`: a repeat `Store` is silently dropped by the repository and the observer never fires, so no second crawl happens.

```mermaid
sequenceDiagram
    autonumber
    participant OP as Operator
    participant APP as main.aro
    participant QH as QueueUrl Handler
    participant REPO as crawled-repository
    participant OBS as Repository Observer
    participant CP as CrawlPage Handler
    participant SP as SavePage Handler
    participant EL as ExtractLinks Handler
    participant NU as NormalizeUrl Handler
    participant FU as FilterUrl Handler
    participant TGT as Target site
    participant FS as ./output

    OP->>APP: ./crawler --url https://example.com
    APP->>QH: Emit QueueUrl {url, base}
    QH->>REPO: Store {id=sha256(url), url, base}
    REPO-->>OBS: new entry (new id)
    OBS->>CP: Emit CrawlPage {url, base}
    CP->>TGT: HTTP GET url
    TGT-->>CP: HTML body
    CP->>CP: ParseHtml → {title, markdown, links}
    par
        CP->>SP: Emit SavePage {url, title, content, base}
        SP->>FS: Write <sha256(url)>.md
    and
        CP->>EL: Emit ExtractLinks {url, links, base}
        loop parallel for each href (concurrency: 16)
            EL->>NU: Emit NormalizeUrl {raw, base}
            NU->>FU: Emit FilterUrl {url, base}
            alt URL passes all FilterUrl guards
                FU->>QH: Emit QueueUrl {url, base}
                QH->>REPO: Store {id, url, base}
                alt id is new
                    REPO-->>OBS: new entry → loop continues
                else id already present
                    Note over REPO,OBS: silent dedup, observer does NOT fire
                end
            else dropped (extension / length / stopword / cross-domain / repeated-segment)
                Note over FU: Log "Skipping ..." when DEBUG=1
            end
        end
    end
```

## 7. Event Payload Relationships

There is no relational schema, but `openapi.yaml` defines six event payloads plus one repository record. The diagram below shows which event carries which fields and how they connect — closest thing to an ER diagram this project has.

```mermaid
classDiagram
    class QueueUrlEvent {
        string url
        string base
    }
    class CrawlRequest {
        string id "sha256(url)"
        string url
        string base
    }
    class CrawlPageEvent {
        string url
        string base
    }
    class SavePageEvent {
        string url
        string title
        string content
        string base
    }
    class ExtractLinksEvent {
        string url
        string[] links
        string base
    }
    class NormalizeUrlEvent {
        string raw
        string base
    }
    class FilterUrlEvent {
        string url
        string base
    }

    QueueUrlEvent --> CrawlRequest : "hash + Store"
    CrawlRequest --> CrawlPageEvent : "Observer emits"
    CrawlPageEvent --> SavePageEvent : "fan-out"
    CrawlPageEvent --> ExtractLinksEvent : "fan-out (links only, no HTML)"
    ExtractLinksEvent --> NormalizeUrlEvent : "per href"
    NormalizeUrlEvent --> FilterUrlEvent : "absolute URL"
    FilterUrlEvent --> QueueUrlEvent : "if not filtered"
```

## What's intentionally not in this document

- **Class diagram.** ARO is event-driven prose, not OO. There are no classes, interfaces, or inheritance trees to draw.
- **Multi-environment deployment.** There is no dev/staging/prod distinction in the repository. The image and binary are produced once per ref / tag and run wherever the operator launches them.
- **Authentication / RBAC.** The crawler has no users beyond the OS user that launches it (`aro` inside the container), and no inbound surface to protect.
- **Database / cache topology.** The repository is in-memory and process-local. It does not survive a restart, by design — the crawl is one-shot.
- **Service-to-service network policies.** Single-process, no peer services.
