# Apparat Blueprint

> **This is a template repository.** It ships the complete platform — backend, frontend,
> infrastructure, CI and release pipeline — with **no business logic**. Use it as the starting
> point for your own Go/React service instead of wiring all of this up from scratch.

**Stack:** Go / Gin / GORM / SQLite on the backend, React / React Admin / Tailwind on the
frontend, with OIDC auth, local infrastructure via Docker Compose, and a release pipeline that
produces a Cosign-signed, SBOM-attested container image.

---

## What you get

| Area             | What is included                                                                                                       |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **Backend**      | Config layering, CLI (cobra), HTTP server, SQLite store with audit callbacks, RFC 7807 errors, health/config endpoints |
| **Frontend**     | Vite + React 19 + React Admin + Tailwind v4 + Flowbite React, runtime config via Zod, OIDC login, theming, layout      |
| **Infra**        | Traefik, Dex, OpenObserve, OTel collector, Redis, RedisInsight, local TLS via mkcert                                   |
| **Tooling**      | `mise` for tool versions and tasks, Overmind for process supervision, Air for backend hot reload                       |
| **CI / Release** | Lint, test, Docker build, SonarCloud, semantic-release, Cosign signing, SBOM attestation                               |

The extension points are deliberately narrow — see [CONCEPT.md](CONCEPT.md) for the architecture
and [AGENTS.md](AGENTS.md) for a precise map of where your code goes.

---

## Tech Stack

- **Backend**
  - [Go](https://go.dev)
  - [Gin Web Framework](https://gin-gonic.com)
  - [GORM](https://gorm.io) + [SQLite](https://www.sqlite.org) (pure-Go driver, no cgo)
  - [Cobra](https://cobra.dev) & [Viper](https://github.com/spf13/viper)
  - [GORM audit callbacks](https://gorm.io/docs/hooks.html) for `created_by` / `modified_by`
- **Frontend**
  - [React](https://react.dev)
  - [Vite](https://vitejs.dev/)
  - [React Admin](https://marmelab.com/react-admin/)
  - [Tailwind CSS v4](https://tailwindcss.com) + [Flowbite React](https://flowbite-react.com)
  - [Zod](https://zod.dev) for runtime config validation
- **Identity & Local Infrastructure**
  - [Dex](https://dexidp.io/) (OIDC provider for local development; swap for any IdP in production)
  - [Traefik](https://traefik.io/) (local edge router)
  - [mkcert](https://github.com/FiloSottile/mkcert) & dnsmasq (local TLS & `.test` routing)
  - [Redis](https://redis.io)
- **Observability**
  - [Sentry](https://sentry.io)
  - [OpenTelemetry](https://opentelemetry.io) + [OpenObserve](https://openobserve.ai/)
- **Development & Ops**
  - [mise](https://mise.jdx.dev/)
  - [Docker](https://www.docker.com) with Cosign signing and SBOM attestation

---

## Quickstart

We use `mise` to manage all tool versions (Go, Node, etc.) and project tasks.

```bash
# 1. Install mise (if not already installed)
curl https://mise.run | sh

# 2. Install mise tools + project dependencies
mise install
mise run deps:install

# 3. Prepare local infrastructure
# Generates local certificates, configures dnsmasq/resolver, and updates /etc/hosts (Linux)
mise run infra:prepare

# 4. Start local services (Traefik, Dex, OpenObserve, Redis)
mise run infra:up

# 5. Start the development server (hot-reload for backend & frontend)
overmind s --timeout 10
```

First run only: `mise run be:setup` creates `backend/data/` and the dummy `backend/cmd/assets/`
that `//go:embed assets` requires to compile. It also copies `backend/.env.example` to
`backend/.env` if that file does not exist yet.

---

## Local Environment

Once the stack is running, you can access the applications via:

| Service      | URL                                    | Credentials                         |
| ------------ | -------------------------------------- | ----------------------------------- |
| Admin UI     | https://apparat-blueprint.test         | — (unless `auth` is enabled)        |
| Dex          | https://dex.apparat-blueprint.test     | `admin@example.com` / `password`    |
| OpenObserve  | https://observe.apparat-blueprint.test | `admin@example.com` / `password123` |
| RedisInsight | https://redis.apparat-blueprint.test   | —                                   |

> **These are development defaults, not secrets.** They are hard-coded in `docker-compose.yaml`
> and `infra/dex-config.yaml` so the stack works immediately after `mise run infra:up`. Replace
> all of them before using any of this outside local development.

Development ports: frontend `3400`, backend `3401`, OTel gRPC `3417` / HTTP `3418`,
Redis `3451`.

---

## Everyday Commands

```bash
mise run be:dev      # backend with hot reload (Air)
mise run fe:dev      # frontend with hot reload (Vite)
mise run test        # all tests with coverage
mise run lint        # Go, TypeScript, Prettier, shell, workflows, dotenv
mise run lint --fix  # same, auto-fixing
mise run build       # full frontend + backend build into ./dist
mise run docker:build # container image
```

---

## Adapting This Template

A few places carry the project name. After `git clone`, search and replace `apparat-blueprint`
with your own name:

| What                        | Where                                                                                                                                                                               |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Go module path              | `backend/go.mod`, every import in `backend/**/*.go`, `Dockerfile`, `.mise/tasks/build`                                                                                              |
| Image / bake target         | `docker-bake.hcl`, `backend/internal/app/config/config.go`                                                                                                                          |
| Local domain                | `.mise/tasks/infra/prepare`, `docker-compose.yaml`, `infra/dex-config.yaml`, `infra/traefik-dynamic.yaml`, `backend/config/config.yaml`, `frontend/vite.config.ts` (`allowedHosts`) |
| Frontend package name/title | `frontend/package.json`, `frontend/package-lock.json`, `frontend/index.html`, `frontend/public/manifest.json`                                                                       |
| SonarCloud project          | `sonar-project.properties`                                                                                                                                                          |
| OCI image metadata          | `docker-bake.hcl`, `.github/workflows/release.yml`                                                                                                                                  |

Then:

1. **Add your models** to `allModels` in `backend/internal/app/store/gorm/store.go`.
2. **Add your endpoints** via the `RegisterAdminRoutes` hook in `backend/internal/app/hub/hub.go`.
3. **Add your admin resources** under `frontend/src/apps/admin/resources/<name>/` and register
   them with `<Resource />` in `frontend/src/apps/admin/Admin.tsx`.
4. **Rename the CLI binary** in `.mise/tasks/build` and `Dockerfile` if you want a different name.
5. **Re-issue the local TLS certificates** by removing `infra/.certs/` and re-running
   `mise run infra:prepare`.

---

## Documentation

- [architecture and extension points](CONCEPT.md)
- [configuration](doc/configuration.md)
- [authentication](doc/auth.md)
- [setting up a global traefik service](doc/global-traefik.md)
- [agent cheat sheet](AGENTS.md)
