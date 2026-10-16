# Concept: Apparat Blueprint

This document describes the **architecture** of the template: how a request flows through the
system, where your code belongs, and which conventions to follow. It intentionally contains no
business logic — that is the point of the template.

## 1. Overview

Apparat Blueprint is a single-binary Go service with an embedded SPA:

- A **Gin** HTTP server serves a JSON API, static media directories, and the compiled React Admin
  frontend (embedded via `//go:embed`).
- Persistence is **SQLite** through GORM, with soft deletes and automatic audit columns.
- **Authentication is optional and external.** When an OIDC provider is configured, routes
  registered on the admin group are protected by JWT validation. When it is not, the API is open —
  which is the default, so the template runs with zero setup.
- Everything needed for local development (identity, observability, caching, object storage,
  TLS) is orchestrated by Docker Compose behind a Traefik reverse proxy.

The design goal is that **every cross-cutting concern is already solved**, and adding a feature
means touching a small, well-defined set of extension points rather than re-architecting.

## 2. Request Flow

```
Browser / curl
      │
      ▼
 Traefik (local TLS termination, *.apparat-blueprint.test)
      │
      ▼
 Gin engine  ──▶ /api/config          public by design (frontend bootstraps from it)
      │        ──▶ /media, /style     static, served from backend/data/
      │        ──▶ /api/admin/*       OIDC-protected when auth.type == "oidc"
      │        ──▶ NoRoute            SPA fallback → assets/index.html
      ▼
 middleware chain: Recovery → Sentry → slog → OpenTelemetry → CORS → Auth
      ▼
 your handlers (RegisterAdminRoutes)
      ▼
 GORM store → SQLite (WAL, foreign keys on, audit callbacks)
```

## 3. Extension Points

These are the only places you need to touch. Everything else is infrastructure.

### 3.1 Models and migrations

`allModels` in `backend/internal/app/store/gorm/store.go` is the single registry. It feeds both
`AutoMigrate` at startup and `PurgeAll` (used by `apparat-blueprint database reset`). A model that
is not in this list is never created.

Embed the provided base structs:

```go
type GormModel struct {  // store/gorm/gormmodel.go
    ID        int64          `json:"id"        gorm:"primarykey"`
    CreatedAt time.Time      `json:"createdAt"`
    UpdatedAt time.Time      `json:"updatedAt"`
    DeletedAt gorm.DeletedAt `json:"deletedAt" gorm:"index"` // soft delete
}

type AuditModel struct {  // store/gorm/audit.go
    CreatedBy  string  `json:"created_by"           gorm:"column:created_by;type:varchar(255);<-:create"`
    ModifiedBy string  `json:"modified_by"          gorm:"column:modified_by;type:varchar(255)"`
    DeletedBy  *string `json:"deleted_by,omitempty" gorm:"column:deleted_by;type:varchar(255);index"`
}
```

Composing them gives you timestamps, soft deletes and an audit trail for free:

```go
type Thing struct {
    GormModel
    AuditModel

    Name  string   `json:"name" gorm:"not null;uniqueIndex"`
    Notes []string `json:"notes" gorm:"serializer:json"` // stored as a JSON array in SQLite
}
```

**Conventions worth keeping:**

- `gorm:"serializer:json"` stores slices and maps natively in a single SQLite column. This keeps
  the JSON API clean for React Admin — no manual encoding/decoding at the edge.
- Use `gorm:"uniqueIndex"` for columns that must stay unique; SQLite enforces it.
- Relationships work as usual (`has many`, `many2many`). Foreign keys are enabled via
  `PRAGMA foreign_keys = ON` in `newStore`.
- No migration files exist. `AutoMigrate` is additive only — it creates and alters tables, it does
  not drop or rewrite columns in a way you can roll back. Treat schema changes with care in
  production.

### 3.2 Audit trail

`RegisterAuditCallbacks` installs `Before("gorm:create" | "update" | "delete")` hooks that read the
current user from the request context:

```go
userID, _ := tx.Statement.Context.Value(domain.UserIDKey).(string)
```

The value is injected by `middleware.AuthMiddleware` from the OIDC `sub` claim. Consequence worth
knowing: **audit columns are only populated for requests that went through the admin group.** Rows
written by background jobs, seeds or tests will have empty audit fields — that is intentional, not a
bug.

Deletes are special: GORM's soft delete only issues an `UPDATE`, so the `before_delete` hook first
writes `deleted_by` with a separate statement, then lets the delete proceed.

### 3.3 API endpoints

`hub.Config.RegisterAdminRoutes func(*gin.RouterGroup)` is the hook. The router group handed to you
is `/api/admin` and already carries the auth middleware when OIDC is enabled. Omit the `auth`
config section and the same group is open.

```go
// cmd/serve.go
RegisterAdminRoutes: func(admin *gin.RouterGroup) {
    admin.GET("/things", listThings)
},
```

`GET /api/config` stays public on purpose — the frontend fetches it during bootstrap before any
token exists. Do not move your endpoints under it.

### 3.4 Error handling

Use the RFC 7807 helpers in `backend/internal/app/hub/errors.go`. They emit a
`application/problem+json` body that React Admin surfaces cleanly, instead of Gin's default
`{"error": "..."}`.

### 3.5 Admin resources

The frontend follows the React Admin resource convention:

```
frontend/src/apps/admin/resources/<name>/
├── index.ts     # default-exports { name, list, edit, create, show }
├── ThingList.tsx
├── ThingEdit.tsx
├── ThingCreate.tsx
└── types.ts
```

Register it in `frontend/src/apps/admin/Admin.tsx`:

```tsx
import thing from "@admin/resources/thing";

<Admin ...>
    <Resource {...thing} />
</Admin>
```

The data provider is `ra-data-json-server`, so **list endpoints must speak its dialect**:

| Concern     | Requirement                                                                   |
| ----------- | ----------------------------------------------------------------------------- |
| Range       | read `?_start` and `?_end` query parameters, clamp them                       |
| Sorting     | read `?_sort=<field>&_order=ASC\|DESC`                                        |
| Total count | return an `X-Total-Count` response header — the provider needs it to paginate |
| Errors      | RFC 7807 problem documents                                                    |

`X-Total-Count` is already exposed to the browser via the CORS `AddExposeHeaders` call in
`createCorsMiddleware`, so no extra CORS work is needed.

### 3.6 Runtime configuration

The frontend does not hard-code its configuration. On boot, `main.tsx` fetches `GET /api/config`
and validates it against `AppConfigSchema` (Zod) before rendering. If validation fails, the app
renders a configuration error screen instead of crashing.

When you add a field, you touch exactly two places:

1. `backend/internal/app/config/model.go` — add it to the relevant config struct, with a
   `mapstructure` tag (that is the key the YAML/env layers bind to) and a `validate` tag.
2. `frontend/src/core/config/config.schemas.ts` — mirror it in the Zod schema.

Config resolution order, later wins:

1. `backend/config/config.yaml` — committed defaults
2. `backend/config/config.local.yaml` — gitignored local overrides (**secrets go here**)
3. `backend/.env` — loaded by `godotenv`; copy from `.env.example`
4. Environment variables — Viper maps `app.log_level` → `APP_LOG_LEVEL`
5. CLI flags

Validation runs before the server starts. `validate` tags are enforced, plus a few hand-written
rules in `validate.go` (database filename charset, date locale shape, Redis URL form).

### 3.7 Observability

Initialisation happens once in `cmd/serve.go`, in order: logger (slog) → Sentry → Redis → store →
OTel → HTTP server. Each piece is a no-op when its config is empty, so the template runs with none
of them configured.

- **Logs** — structured `slog`, JSON in the server, text for CLI subcommands. Keys are snake_case.
- **Traces** — OTel via `otelgin`, OTLP over gRPC to the local collector, which forwards to
  OpenObserve. The service name comes from `config.OtelServiceName`.
- **Errors** — Sentry for both server and browser. Both are disabled while the DSN is empty.

The same request context carries the user ID for auditing, so traces and audit rows line up.

## 4. Security Model

- **No auth by default.** The `auth` section is absent from `config.yaml`, so `/api/admin` is open.
  Enable it by configuring an OIDC provider (see [doc/auth.md](doc/auth.md)) before exposing the
  service to anything but localhost.
- **`auth.skip_tls_verify`** is refused in production — the server refuses to start.
- **Secrets belong in `config.local.yaml`** (gitignored) or environment variables. Never in
  `config.yaml`, never in a `VITE_*` variable: those are compiled into the browser bundle.
- The credentials in `docker-compose.yaml` and `infra/dex-config.yaml` are well-known
  **development defaults**. Replace them for any non-local deployment.

## 5. Deployment Shape

The build produces a single static binary with the frontend embedded:

```
mise run build       # frontend -> backend/cmd/assets -> go build -> ./dist/apparat-blueprint
mise run docker:build
```

- Dockerfile builds frontend and backend in separate stages, then a minimal runtime stage running
  as a non-root user.
- `docker-bake.hcl` builds multi-arch (`linux/amd64`, `linux/arm64`) and stamps OCI metadata.
- Release is semantic-release driven; images are signed with Cosign and attested with an SBOM.
- `./dist/.env` is generated from `backend/.env.example` — review it before shipping.

Configuration is injected at runtime via environment variables, so the same image runs in every
environment.

## 6. Conventions Summary

| Area       | Convention                                                            |
| ---------- | --------------------------------------------------------------------- |
| Go logging | `slog` only; `logrus` is blocked by depguard; snake_case keys         |
| Go random  | `math/rand/v2`, never `math/rand`                                     |
| Go errors  | wrap with `%w`; surface to clients via the RFC 7807 helpers           |
| Go layout  | gofumpt + golines (120 columns) enforced by golangci-lint             |
| TS logging | `no-console` and `no-alert` are errors; use the `logger` module       |
| TS naming  | camelCase for variables/paths; PascalCase for components              |
| Frontend   | Tailwind v4 must stay wired in three places or styles silently vanish |
| Commits    | Conventional Commits — the Angular preset drives semantic-release     |
