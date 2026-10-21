# Café Raíces y Cultura (CRC) — Claude Context

## Project overview
Phoenix LiveView app for a café that doubles as its POS: public site (menu, events, collaborations, customer bill page), waiter order-taking, kitchen/bar display stations, staff self-service (schedules, attendance, shift log, internal production), and a full admin panel (catalog, inventory, sales/finance reports, CRM + loyalty, HR).

## Stack
- **Elixir 1.18** (Docker image pins 1.18.3 / OTP 27.3) · **Phoenix 1.8** · **LiveView 1.2**
- **PostgreSQL** — local DB: `crc_dev`
- **Tailwind CSS v4** + **DaisyUI** (themes: `cafe-light` / `cafe-dark`, follows OS preference)
- **Cloudinary** — image uploads (menu items, event photos, user avatars)
- **Swoosh + Brevo** — transactional email via `CRC.BrevoAdapter` (production only; dev uses `Swoosh.Adapters.Local` → `/dev/mailbox`)
- **NimbleCSV** — admin CSV reports (UTF-8 BOM)

## Essential commands
```bash
# Start dev server
mix phx.server                  # → http://localhost:4000

# Database
mix ecto.reset                  # drop + create + migrate + seed
mix ecto.migrate                # run pending migrations
mix ecto.rollback               # roll back last migration

# Code quality
mix compile                     # compile and check for errors
mix test                        # run test suite (~1619 tests, 34 known pre-existing failures — compare against this baseline, don't assume a failure is new)
mix precommit                   # compile --warning-as-errors + deps.unlock --unused + format + test
mix esbuild crc                 # force-rebuild the JS bundle if a hook change doesn't show up (profile is `crc`)

# Generate a new migration
mix ecto.gen.migration name
```

## Architecture — bounded contexts
| Context | Path | Responsibility |
|---|---|---|
| `CRC.Catalog` | `lib/crc/catalog/` | Menu items, categories, packages |
| `CRC.Bookings` | `lib/crc/bookings/` | Reservations |
| `CRC.Media` | `lib/crc/media/` | Home carousel photos |
| `CRC.Events` | `lib/crc/events/` | Events, collaborators, event types |
| `CRC.Accounts` | `lib/crc/accounts/` | Users, roles, auth |
| `CRC.Inventory` | `lib/crc/inventory/` | Products (insumos), suppliers, stock |
| `CRC.Orders` | `lib/crc/orders/` | Orders, tables, kitchen/bar flow, sales/finance stats, employee performance |
| `CRC.CRM` | `lib/crc/crm.ex`, `lib/crc/crm/` | Customers, visits, loyalty rewards/redemptions, personal packages |
| `CRC.HR` | `lib/crc/hr.ex`, `lib/crc/hr/` | Work schedules, attendance (geolocated clock-in) |
| `CRC.Schedule` | `lib/crc/schedule/` | Areas, tasks, staff assignments |
| `CRC.Production` | `lib/crc/production/` | Internal recipes and production logs |
| `CRC.ShiftNotes` | `lib/crc/shift_notes/` | Shift log (bitácora) |
| `CRC.Reports` | `lib/crc/reports.ex` | CSV report builders (finanzas, desperdicio, ventas) |
| `CRC.Settings` | `lib/crc/settings.ex`, `lib/crc/settings/` | Café hours, discounts |

## Routes by audience (`lib/crc_web/router.ex`)
| Scope | Auth | Examples |
|---|---|---|
| Public | none | `/`, `/menu`, `/colaboraciones`, `/cuenta/:token` (customer bill), password reset |
| Staff / employee | any logged-in user | `/mesa` (waiter), `/cocina`, `/barra`, `/bitacora`, `/produccion`, `/faltantes`, `/mi-horario`, `/mi-perfil` |
| Admin | `role: "admin"` | `/admin/*` (~28 LiveViews, `admin` layout) + `/admin/reportes/*.csv` |

Note: staff routes only check that a session exists — they don't check role or `is_active`.

## Order lifecycle (`CRC.Orders`)
1. Order opened (`dine_in` / takeout / group). Items: menu items, packages (one `order_item` per dish, shared `package_id`), product extras, variants (`variant_id` + `for_menu_item_id`), ingredient exclusions.
2. `send_to_kitchen/1` — in one transaction: prepared items → `sent`, `destination: "retail"` items → `served` directly, ingredient stock deducted (locks products, fails with `{:insufficient_stock, name}`). Broadcasts on PubSub `"orders"`, `"menu_stock"`, `"admin:products"`.
3. Stations mark items `ready` → `served` (`mark_item_ready/2`, `mark_item_served/2`).
4. `close_order/3` — subtotal from items, discount applied; `orders.total` is **post-discount**, `discount_percentage` stored separately. Then an isolated loyalty hook (never rolls back a payment).
5. `remove_item/1` cascades to dependent pending extras/variants and to the rest of the same package.

## Key files
| File | Purpose |
|---|---|
| `lib/crc_web/router.ex` | All routes; future scopes commented and ready |
| `lib/crc_web/live/home_live.ex` | Public single-page LiveView |
| `lib/crc_web/live/admin/` | All admin LiveViews |
| `lib/crc_web/live/waiter/order_live.ex` | Waiter order screen (largest LiveView; split Menú/Comanda layout) |
| `lib/crc_web/components/admin_components.ex` | Shared admin UI (`panel`, `stat_card`, `admin_modal`, `admin_table_head`, `period_filter`, `step_link`) + `nav_sections/0` — the single source of truth for the admin card grid |
| `lib/crc_web/user_auth.ex` | Auth plugs + `on_mount` hooks; sessions last 8h, renewed on every request |
| `assets/css/app.css` | DaisyUI themes (`cafe-light`, `cafe-dark`) |
| `assets/js/app.js` | Hooks: `CarouselAutoplay`, `SoundNotifier`, `GeolocationClockIn`, `FloorMapEditor`, `DismissableTip`, `AutoDismissFlash` (new hooks must be added to the `LiveSocket` `hooks:` map) |
| `priv/repo/seeds.exs` | Seed data (categories, menu items, carousel photos) |
| `lib/crc/cloudinary.ex` | Cloudinary upload client |
| `config/runtime.exs` | Production config (reads env vars) |

## DaisyUI brand palette (`cafe-light` theme)
| Token | Value | Use |
|---|---|---|
| `base-100` | `oklch(97% 0.015 78)` | Warm cream background |
| `primary` | `oklch(42% 0.085 45)` | Coffee brown — main actions |
| `secondary` | `oklch(63% 0.10 42)` | Terracotta |
| `accent` | `oklch(70% 0.13 68)` | Caramel/gold |

## Language rules
- **UI text** → always in **Spanish**
- **Code** (variables, functions, modules, comments) → always in **English**

## Responsive design rules
- **Mobile-first** with Tailwind breakpoints (`sm:`, `md:`, `lg:`)
- Admin list views: **cards on mobile** (`md:hidden`) + **table on desktop** (`hidden md:block`)
- Never use fixed widths (`w-40`, `w-48`) on inputs/elements that sit inside flex rows on mobile — use `w-full sm:w-auto` instead
- Modal form grids: always `grid-cols-1 sm:grid-cols-2`, never `grid-cols-2` alone

## File upload pattern (LiveView)
- `live_file_input` **must** be inside a `<form>` wrapper for upload channels to initialize
- `consume_uploaded_entries/3` returns a **plain list** (not a `{list, socket}` tuple) in LiveView 1.1+
- Drop zone UI: hidden `<.live_file_input class="sr-only" />` inside a styled `<label for={@uploads.name.ref}>`

## Deployment
- **Git remote**: `github.com:amirOrbe/cafe-raices-y-cultura.git` (branch: `master`)
- **Hosting**: Fly.io — app `crc-app`, Postgres `crc-db`, region `dfw` (migrated from Gigalixir 2026-09-30; Gigalixir kept frozen — 0 replicas — as a rollback safety net, not yet decommissioned)
- **Workflow**: push to GitHub first → test locally → deploy to Fly only when user explicitly approves
- **Fly deploy**: `fly deploy -a crc-app` (builds via `Dockerfile`, remote builder — no local Docker needed)
- **Migrations**: run automatically two ways — `[deploy] release_command = "/app/bin/migrate"` in `fly.toml` (before the app machine starts) **and** `CRC.Release.migrate/0` on every app boot (`CRC.Application.start/2`), which now retries with backoff (up to 12× / 5s) since a freshly-booted Fly Machine's private-network DNS can take a few seconds to come up
- **Required secrets on Fly** (`fly secrets set ... -a crc-app`): `DATABASE_URL` (set automatically by `fly postgres attach`), `SECRET_KEY_BASE`, `POOL_SIZE`, `CLOUDINARY_API_SECRET`, `BREVO_API_KEY`, `BREVO_SMTP_LOGIN`, `BREVO_SMTP_PASSWORD`, `MAILER_FROM_ADDRESS`, **`ECTO_IPV6=true`** (critical — Fly's private network (6PN) is IPv6-only; without this Postgrex can't resolve `crc-db.flycast`)
- `PHX_HOST` and `PORT` are set in `fly.toml`'s `[env]`, not as secrets
- **Legacy Gigalixir commands** (kept for rollback reference only): `git push gigalixir master`, `gigalixir ps:migrate` — see `~/.claude/.../memory/reference_gigalixir_cli.md` for CLI gotchas

## Cloudinary config (production)
```
cloud_name: "dekekqq8b"
api_key:    "263497645159344"
api_secret: set via CLOUDINARY_API_SECRET env var
```

## Do NOT
- Commit `.env` files or secrets
- Use `mix ecto.drop` in production
- Deploy to Fly (`fly deploy`) or push to Gigalixir without explicit user approval
- Use `table` layout without `table-fixed` + explicit column widths (causes horizontal overflow)
- Place `w-40` date inputs side-by-side without `flex-col sm:flex-row` wrapping
