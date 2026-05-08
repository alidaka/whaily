# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
mix setup              # Install deps and build assets (first-time setup)
mix phx.server         # Run dev server at localhost:4000
iex -S mix phx.server  # Dev server with interactive Elixir shell
mix test               # Run test suite
mix assets.build       # Rebuild JS/CSS for dev
mix assets.deploy      # Minified assets for production
```

## Environment Variables

Copy `.envrc.example` to `.envrc` (uses direnv). Required vars:

- `FRED_KEY` — Federal Reserve FRED API key
- `OBA_KEY` — OneBusAway API key
- `OBA_STOPS` — Comma-separated bus stop IDs to monitor
- `WEATHER_LAT` / `WEATHER_LONG` — Coordinates for weather data
- `SECRET_KEY_BASE` — Phoenix secret (generate with `mix phx.gen.secret`)

## Architecture

**Whaily** is a Phoenix LiveView dashboard aggregating real-time data: weather, local buses, food trucks, beer taps, and economic indicators.

### Key File

`lib/whaily_web/controllers/page_controller.ex` is the core of the app (~520 lines). It is the sole LiveView and handles everything: mounting async tasks that hit 5 external APIs in parallel, parsing responses, and rendering the dashboard. All data-fetching logic lives here.

### Data Sources

| Source | API | Data |
|--------|-----|------|
| Open-Meteo | REST | Temperature + precipitation forecast |
| OneBusAway | REST | Real-time bus arrival predictions |
| Google Calendar | REST | Food truck (Chuck's Hop Shop) schedule |
| FRED (Federal Reserve) | REST | Treasury yields + mortgage rates |
| taplists.web.app | Scraping | Beer tap list (fresh hops, hazies, darks) |

### Frontend

JavaScript is colocated inside HEEX templates in `page_controller.ex` as Phoenix LiveView hooks. Two Chart.js instances are created as hooks:
- `.WeatherChart` — temperature + precipitation
- `.EconomicChart` — Treasury + mortgage rates

`assets/js/app.js` bootstraps LiveView and loads colocated hooks. CSS is Tailwind 3 compiled via the Mix asset pipeline (esbuild + tailwind).

### OTP Supervision

`lib/whaily/application.ex` starts: Telemetry, DNSCluster, PubSub, Finch (HTTP client), and the Phoenix Endpoint. HTTP calls use Finch with Jason for JSON parsing.

### Deployment

Deployed to Fly.io (Seattle region). Pushing to `main` triggers auto-deploy via `.github/workflows/fly-deploy.yml`. Runtime secrets are set via `fly secrets set`.
