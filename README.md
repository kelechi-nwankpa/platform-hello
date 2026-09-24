# platform-hello

The IDP's first golden path service — proves the observability triangle works with real service data

Scaffolded from [nodejs-fastify-svc](https://github.com/kelechi-nwankpa/internal-developer-platform/tree/main/templates/nodejs-fastify-svc) — the IDP's Node.js golden path template ([ADR-0031](https://github.com/kelechi-nwankpa/internal-developer-platform/blob/main/docs/adr/0031-golden-path-template-nodejs-fastify.md)).

## What you get out of the box

- **Fastify 5** (TypeScript, ES modules, distroless container)
- **OpenTelemetry auto-instrumentation** → traces to Tempo via OTLP HTTP
- **pino** structured JSON logger with `trace_id` injection on every line
- **prom-client** `/metrics` endpoint scraped by Prometheus
- **S3 bucket** provisioned by [Crossplane ObjectBucket XRD](https://github.com/kelechi-nwankpa/internal-developer-platform/blob/main/docs/adr/0027-first-xrd-objectbucket.md)
- **cert-manager Certificate** for TLS on the Ingress
- **ArgoCD Application** for GitOps deployment
- **Backstage Component entity** so this service shows up in the developer portal

## Local development

Requires Node 22 (see [`.nvmrc`](.nvmrc) or use `nvm use 22`).

```bash
# Install dependencies
npm install

# Set OTel env vars pointing at your local OTel Collector (assumes kubectl port-forward)
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_SERVICE_NAME=platform-hello
export OTEL_RESOURCE_ATTRIBUTES="service.namespace=platform-team,deployment.environment=local"

# Hot-reload dev server
npm run dev

# Send a request → generates a span → check Grafana Tempo Explore
curl http://localhost:3000/hello
```

## Endpoints

| Path | Purpose |
|---|---|
| `GET /healthz` | Liveness probe (200 = process alive) |
| `GET /readyz` | Readiness probe (200 = ready to serve traffic) |
| `GET /metrics` | Prometheus metrics (default Node.js metrics + custom counters) |
| `GET /hello` | Example endpoint — touches S3 bucket to demonstrate infra integration |

## Building the container

```bash
npm run docker:build   # → platform-hello:local
npm run docker:run     # runs locally with .env
```

## Deploying to the platform

The [`kubernetes/`](kubernetes/) directory has all resources needed:

- `deployment.yaml` — 2 replicas, distroless image, envFrom the ExternalSecret + ObjectBucket connection secret
- `service.yaml` — ClusterIP
- `servicemonitor.yaml` — Prometheus scrape config (labels match kube-prometheus-stack's selector after the ADR-0024 postscript fix)
- `externalsecret.yaml` — ESO CR pulling app config from Vault at `secret/platform-team/platform-hello`
- `objectbucket.yaml` — Crossplane XRC that provisions the S3 bucket + writes connection secret
- `certificate.yaml` — cert-manager Certificate (SelfSigned issuer on kind, Let's Encrypt on EKS)
- `ingress.yaml` — routes traffic at `https://platform-hello.idp.seniormankelz.dev/`

Deploy via ArgoCD:

```bash
# Copy argocd/application.yaml into the platform repo
cp argocd/application.yaml <platform-repo>/platform/argocd/apps/platform-hello.yaml
git -C <platform-repo> add . && git -C <platform-repo> commit -m "feat: deploy platform-hello"
git -C <platform-repo> push
# ArgoCD's root app-of-apps picks it up on next reconcile
```

## Observability drill-down

Once deployed + serving traffic:

- **Grafana Explore → Prometheus:** `up{job="platform-hello"} == 1` → confirms scraping
- **Grafana Explore → Loki:** `{app="platform-hello"}` → structured JSON logs with `trace_id` on every line
- **Grafana Explore → Tempo:** search by service name `platform-hello` → trace waterfall
- **Cross-link:** click any log line with `trace_id` → "View Trace" button jumps to Tempo. Click a span in Tempo → "Logs for this span" jumps back to Loki filtered by span tags + time window.

## Interview talking points

- "This is a **golden path template output** — scaffolded from the IDP in ~10 minutes vs the industry-standard 2 days."
- "OpenTelemetry SDK is loaded **before any other import** in `src/index.ts` — auto-instrumentation only works if OTel wraps modules at import time."
- "Structured logging with **trace_id injection** via pino mixin is what makes Grafana's `derivedFields` cross-link work. Regex extracts `trace_id=<hex>` from any log line, click → jump to Tempo."
- "Distroless container: no shell, no libc, runs as non-root UID 65532. Attack surface roughly the same as running the Node binary bare."
- "Every service gets an S3 bucket from a Crossplane **ObjectBucket XRC** — one YAML in `kubernetes/objectbucket.yaml`. On kind, materialises against MinIO; on EKS, against real AWS S3. Same YAML, different backend."
