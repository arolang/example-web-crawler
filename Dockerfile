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
FROM ghcr.io/arolang/aro-buildsystem:0.9.6 AS builder

WORKDIR /app
COPY *.aro ./

# Validate the application
RUN aro check .

# Build native binary
RUN aro build . --release -o crawler

# -----------------------------------------------------------------------------
# Stage 2: Minimal runtime container
# -----------------------------------------------------------------------------
FROM ghcr.io/arolang/aro-runtime:0.9.6

LABEL org.opencontainers.image.title="ARO Web Crawler"
LABEL org.opencontainers.image.description="Example web crawler built with ARO language"

# Switch to root to copy binary and set permissions
USER root

# Copy compiled binary
COPY --from=builder /app/crawler /usr/local/bin/crawler

# Create output directory
RUN mkdir -p /output && chown aro:aro /output

# Switch back to non-root user
USER aro
WORKDIR /output

ENTRYPOINT ["/usr/local/bin/crawler"]
