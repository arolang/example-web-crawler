# Operations

## Deployment surfaces

The CI pipeline produces two artifacts:

1. **Container image** — Kaniko-built from `Dockerfile`, scanned by Trivy, pushed by `crane` to the project's GitLab Container Registry on default-branch and tag builds. Tags: `<ref-slug>-<short-sha>` always; additionally `:latest` on default branch, `:<git-tag>` on tag.
2. **Native Linux amd64 binary** — built by `aro build . --release` only on tag pushes (`package_linux_amd64` job), tarred with the README, sha256'd, uploaded to the GitLab generic package registry, and attached to a GitLab Release.

There is no Kubernetes manifest, Helm chart, or Terraform in this repository. The crawler is a one-shot batch process; an operator runs it on demand or wires it into a parent scheduler.

## Running in production

```bash
docker run --rm \
  -v /path/on/host:/output \
  -e DEBUG=1 \
  -e MAX_URL_LENGTH=300 \
  -e SKIP_WORDS_IN_URL=login,logout,admin \
  $CI_REGISTRY_IMAGE:latest \
  --url https://example.com
```

The container runs as `aro:aro` (non-root) with `/output` as working directory; the entrypoint is `/usr/local/bin/crawler`. Anything passed after the image name is forwarded as crawler args.

## Health and lifecycle

- **No health probe.** The process is a CLI tool. It runs until the event queue drains, then exits 0. There is no `/healthz` endpoint to scrape.
- **No graceful shutdown signal.** A SIGTERM during a crawl terminates the process; partially-written `.md` files may exist (whatever `Write the <content> to the <file: ...>` had flushed by then). Re-running with the same seed will skip already-fetched URLs only if you also persist the dedup repository — currently you don't, so the next run re-crawls.
- **Exit code.** `0` on success. Non-zero on any ARO runtime error (unhandled event extraction failure, HTTP error propagated by `Request`, filesystem write error).

## Observability

| Signal | How |
|---|---|
| Stdout/stderr logs | All `Log ... to the <console>` calls. With `DEBUG=1`, every queued and every skipped URL is logged. Without `DEBUG`, only application-level milestones (`Starting Web Crawler...`, `Web Crawler completed!`, the metrics table). |
| Metrics table | `Application-End` logs `<metrics: table>` — ARO's built-in run-time stats. Printed once on shutdown. |
| Output dir | `output/` filling up is the proxy for "the crawl is making progress". |

There is no structured-JSON logger, no Prometheus endpoint, no tracing. <!-- TODO: confirm whether the wiki's logging/monitoring standard (structured JSON, required fields) is expected for batch CLI tools. -->

## CI/CD pipeline

`.gitlab-ci.yml` stages, in order:

| Stage | Job | Trigger |
|---|---|---|
| `test` | `Check` (`aro check .`) | every push |
| `build` | `Build` (Kaniko → `image.tar` artifact) | every push |
| `scan` | `security_scan` (Trivy on `image.tar`), `kics-iac-sast`, `secret_detection` | default branch, tags, `feature/*` |
| `publish` | `Publish` (`crane push`) | default branch, tags |
| `package` | `package_linux_amd64` (binary tar.gz + sha256 to package registry) | tags only |
| `release` | `release` (GitLab Release with binary asset links) | tags only |

`security_scan` fails the pipeline on MEDIUM/HIGH/CRITICAL CVEs unless the pipeline variable `ALLOW_VULNERABLE=yes` is set. Exclusions live in `.trivyignore`.

## Known issues and gotchas

- **One crawl, one process.** The dedup repository is in-memory only. Re-running the binary re-crawls from scratch; do not expect resume-on-restart semantics.
- **Same-domain guard is substring-based.** `FilterUrl Handler` enforces `when <clean-url> contains <base-domain>`. If the base domain string appears in a path or query of a different host, it would be accepted — this is theoretical but worth noting if you start crawling sites that link to each other under predictable paths.
- **`MAX_URL_LENGTH=0` disables the length check.** The default is `0` (unlimited). `0` is treated as a sentinel by the Emit guard `(<max-length> == 0 or <url-length> <= <max-length>)`.
- **`SKIP_WORDS_IN_URL` is token-based, not substring.** `en` matches `/en/` but not `/engineering/`. If you need substring matching, that requires a structural change (per-word events into a side repository) — see prior conversation in commit history if revisiting.
- **No retry policy on HTTP errors.** `Request the <response> from the <url>` either succeeds or aborts the handler; downstream events for that URL never fire, but the crawl continues with other queued URLs.
- **The container base images are pinned to `0.11.2`.** Both `ghcr.io/arolang/aro-buildsystem:0.11.2` and `ghcr.io/arolang/aro-runtime:0.11.2` are version-pinned in the `Dockerfile`, matching `ARO_BUILD_IMAGE` in `.gitlab-ci.yml`. Bump all three together when upgrading the toolchain. <!-- TODO: pin to a sha256 digest for full reproducibility once needed. -->
- **`--depth` is optional.** Without it the crawler follows every same-domain link (dedup keeps each URL to a single fetch); `--depth <n>` caps how many levels deep it descends (`1` = seed page only).
