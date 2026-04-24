# Café Raíces y Cultura (CRC) — Claude Context

## Project overview
Phoenix LiveView web app for a café: public menu page, event gallery, and a full admin panel.

## Stack
- **Elixir 1.18.4** · **Phoenix 1.8.5** · **LiveView 1.1**
- **PostgreSQL** — local DB: `crc_dev`
- **Tailwind CSS v4** + **DaisyUI** (themes: `cafe-light` / `cafe-dark`)
- **Cloudinary** — image uploads (menu items, event photos, user avatars)
- **Swoosh + Resend** — transactional email (production only)

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
mix test                        # run test suite

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
| `CRC.Orders` | `lib/crc/orders/` | Sales, kitchen display, performance |
| `CRC.Settings` | `lib/crc/settings/` | App-wide config |

## Key files
| File | Purpose |
|---|---|
| `lib/crc_web/router.ex` | All routes; future scopes commented and ready |
| `lib/crc_web/live/home_live.ex` | Public single-page LiveView |
| `lib/crc_web/live/admin/` | All admin LiveViews |
| `assets/css/app.css` | DaisyUI themes (`cafe-light`, `cafe-dark`) |
| `assets/js/app.js` | `CarouselAutoplay` hook |
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
- `consume_uploaded_entries/3` returns a **plain list** (not `{list, socket}` tuple) in LiveView 1.1+
- Drop zone UI: hidden `<.live_file_input class="sr-only" />` inside a styled `<label for={@uploads.name.ref}>`

## Deployment
- **Git remote**: `github.com:amirOrbe/cafe-raices-y-cultura.git` (branch: `master`)
- **Hosting**: Gigalixir
- **Workflow**: push to GitHub first → test locally → deploy to Gigalixir only when user explicitly approves
- **Gigalixir deploy**: `git push gigalixir master`
- **Run migrations on Gigalixir**: `gigalixir ps:migrate`
- **Required env vars on Gigalixir**: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `CLOUDINARY_API_SECRET`, optionally `RESEND_API_KEY`, `MAILER_FROM_ADDRESS`

## Cloudinary config (production)
```
cloud_name: "dekekqq8b"
api_key:    "263497645159344"
api_secret: set via CLOUDINARY_API_SECRET env var
```

## Do NOT
- Commit `.env` files or secrets
- Use `mix ecto.drop` in production
- Push directly to Gigalixir without user approval
- Use `table` layout without `table-fixed` + explicit column widths (causes horizontal overflow)
- Place `w-40` date inputs side-by-side without `flex-col sm:flex-row` wrapping
