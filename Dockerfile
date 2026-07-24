# =============================================================================
# ARO Web Crawler - Multi-stage Docker Build
# =============================================================================
# Build:  docker build -t aro-crawler .
# Run:    docker run -v $(pwd)/output:/output aro-crawler --url https://example.com
# =============================================================================
# This Dockerfile uses the official ARO Docker images from GitHub Container
# Registry (ghcr.io/arolang/aro-buildsystem and ghcr.io/arolang/aro-runtime)
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build the web crawler using ARO buildsystem
# -----------------------------------------------------------------------------
FROM ghcr.io/arolang/aro-buildsystem:0.11.2 AS builder

WORKDIR /app
COPY *.aro ./

# Validate the application
RUN aro check .

# Build native binary
RUN aro build . --release -o crawler

# -----------------------------------------------------------------------------
# Stage 2: Minimal runtime container
# -----------------------------------------------------------------------------
FROM ghcr.io/arolang/aro-runtime:0.11.2

LABEL org.opencontainers.image.title="ARO Web Crawler"
LABEL org.opencontainers.image.description="Example web crawler built with ARO language"

# Switch to root to copy binary and set permissions
USER root

# The aro 0.11.2 binary links libgit2.so.1.1, which the runtime image does not
# ship. Install it (same Ubuntu 22.04 base as the buildsystem) so the dynamic
# loader can resolve it at startup.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgit2-1.1 \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binary
COPY --from=builder /app/crawler /usr/local/bin/crawler

# aro 0.11.2 loads the event-schema registry from openapi.yaml next to the
# binary at runtime (earlier versions embedded it at build time). Without it,
# typed event extraction is disabled and CrawlPage emits fail.
COPY openapi.yaml /usr/local/bin/openapi.yaml

# Create output directory
RUN mkdir -p /output && chown aro:aro /output

# Switch back to non-root user
USER aro
WORKDIR /output

ENTRYPOINT ["/usr/local/bin/crawler"]
