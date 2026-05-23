# ARO Web Crawler — Documentation

A single-binary, event-driven web crawler written in [ARO](https://arolang.github.io/aro/). Fetches a website, converts each page to Markdown, and writes one `.md` file per page to `./output/`.

This folder holds service-level documentation. For the higher-level architecture overview with diagrams, see `../ARCHITECTURE.md`. For Claude Code authoring notes (ARO idioms, invariants, gotchas), see `../CLAUDE.md`. For the quick-start, see `../README.md`.

## Contents

| Doc | Purpose |
|---|---|
| [setup.md](./setup.md) | Local development setup, prerequisites, env vars, run/build commands |
| [architecture.md](./architecture.md) | Service-level architecture summary (links to `../ARCHITECTURE.md` for diagrams) |
| [api.md](./api.md) | Event payload surface (no HTTP API). Points to `../openapi.yaml` |
| [operations.md](./operations.md) | Deployment, configuration, observability, known issues |

