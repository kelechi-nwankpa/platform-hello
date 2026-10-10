# syntax=docker/dockerfile:1.7
# ─────────────────────────────────────────────────────────────────────
# Multi-stage build for platform-hello
# Stage 1 (builder): Node 22 with npm — install + compile TS
# Stage 2 (runtime): distroless nodejs22 — no shell, no libc,
#                    non-root user. Small attack surface.
# ─────────────────────────────────────────────────────────────────────

# ---- Stage 1: build ----
FROM node:22-slim AS builder

WORKDIR /app

# Install deps first (cached layer if package files unchanged)
COPY package.json ./
RUN npm install --omit=dev --ignore-scripts && \
    cp -r node_modules /app/node_modules_prod && \
    npm install --ignore-scripts

# Copy source + compile
COPY tsconfig.json ./
COPY src ./src
RUN npx tsc

# ---- Stage 2: runtime ----
# distroless nodejs22:nonroot — no shell, runs as UID 65532
# Pinned to digest for two reasons:
#   1. Reproducibility — the same code always builds the same image
#   2. Defeat GitHub Actions buildx cache — pulling by digest guarantees
#      a fresh base image, which matters for security patches (openssl
#      updates in the base land here on next cache miss)
# Rotate this digest on every monthly security review by querying:
#   curl -sI https://gcr.io/v2/distroless/nodejs22-debian12/manifests/nonroot \
#     -H "Accept: application/vnd.oci.image.index.v1+json" \
#     | grep -i docker-content-digest
# Last rotated: 2026-10-10
FROM gcr.io/distroless/nodejs22-debian12:nonroot@sha256:13593b7570658e8477de39e2f4a1dd25db2f836d68a0ba771251572d23bb4f8e

WORKDIR /app

# Copy prod deps only (not dev)
COPY --from=builder --chown=nonroot:nonroot /app/node_modules_prod ./node_modules
COPY --from=builder --chown=nonroot:nonroot /app/dist ./dist
COPY --from=builder --chown=nonroot:nonroot /app/package.json ./

# Distroless nodejs images use `node` as ENTRYPOINT. Just pass the script.
CMD ["dist/index.js"]

EXPOSE 3000

# Kubernetes labels (OCI standard)
LABEL org.opencontainers.image.title="platform-hello" \
      org.opencontainers.image.description="The IDP's first golden path service — proves the observability triangle works with real service data" \
      org.opencontainers.image.source="https://github.com/kelechi-nwankpa/platform-hello"
