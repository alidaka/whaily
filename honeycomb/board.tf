# ============================================================
# Columns for whaily dataset
# ============================================================

resource "honeycombio_column" "error" {
  name        = "error"
  type        = "boolean"
  description = "Whether the span represents an error"
  dataset     = var.dataset
}

resource "honeycombio_column" "net_peer_ip" {
  name        = "net.peer.ip"
  type        = "string"
  description = "Client IP address"
  dataset     = var.dataset
}

resource "honeycombio_column" "http_route" {
  name        = "http.route"
  type        = "string"
  description = "HTTP route template (e.g. /:slug, /admin)"
  dataset     = var.dataset
}

resource "honeycombio_column" "phoenix_action" {
  name        = "phoenix.action"
  type        = "string"
  description = "Phoenix action name"
  dataset     = var.dataset
}

resource "honeycombio_column" "phoenix_controller" {
  name        = "phoenix.controller"
  type        = "string"
  description = "Phoenix controller module"
  dataset     = var.dataset
}

resource "honeycombio_column" "http_user_agent" {
  name        = "http.user_agent"
  type        = "string"
  description = "HTTP User-Agent header"
  dataset     = var.dataset
}

# ============================================================
# Query: Unique visitor IPs over time (unique session proxy)
# ============================================================

data "honeycombio_query_specification" "unique_visitor_sessions" {
  calculation {
    op     = "COUNT_DISTINCT"
    column = "net.peer.ip"
  }

  # Only root spans (one per HTTP request)
  filter {
    column = "trace.parent_id"
    op     = "does-not-exist"
  }

  # Only HTTP requests (not background DB or internal spans)
  filter {
    column = "http.route"
    op     = "exists"
  }

  time_range = 3600
}

resource "honeycombio_query" "unique_visitor_sessions" {
  dataset    = var.dataset
  query_json = data.honeycombio_query_specification.unique_visitor_sessions.json

  depends_on = [
    honeycombio_column.net_peer_ip,
    honeycombio_column.http_route,
  ]
}

resource "honeycombio_query_annotation" "unique_visitor_sessions" {
  dataset     = var.dataset
  name        = "Unique Visitor Sessions"
  description = "Distinct client IPs seen on HTTP root spans — a proxy for unique user sessions. Requires net.peer.ip from Phoenix OTel instrumentation."
  query_id    = honeycombio_query.unique_visitor_sessions.id
}

# ============================================================
# Query: Requests by route
# ============================================================

data "honeycombio_query_specification" "requests_by_route" {
  calculation {
    op = "COUNT"
  }

  filter {
    column = "trace.parent_id"
    op     = "does-not-exist"
  }

  filter {
    column = "http.route"
    op     = "exists"
  }

  breakdowns = ["http.route"]

  order {
    op    = "COUNT"
    order = "descending"
  }

  time_range = 3600
}

resource "honeycombio_query" "requests_by_route" {
  dataset    = var.dataset
  query_json = data.honeycombio_query_specification.requests_by_route.json

  depends_on = [honeycombio_column.http_route]
}

resource "honeycombio_query_annotation" "requests_by_route" {
  dataset     = var.dataset
  name        = "Request Count by Route"
  description = "Total HTTP requests per route over time. Useful for identifying the most-trafficked pages and spotting unusual traffic patterns."
  query_id    = honeycombio_query.requests_by_route.id
}

# ============================================================
# Query: Errors by route
# ============================================================

data "honeycombio_query_specification" "errors_by_route" {
  calculation {
    op = "COUNT"
  }

  filter {
    column = "error"
    op     = "="
    value  = true
  }

  filter {
    column = "trace.parent_id"
    op     = "does-not-exist"
  }

  breakdowns = ["http.route", "http.status_code"]

  order {
    op    = "COUNT"
    order = "descending"
  }

  time_range = 3600
}

resource "honeycombio_query" "errors_by_route" {
  dataset    = var.dataset
  query_json = data.honeycombio_query_specification.errors_by_route.json

  depends_on = [
    honeycombio_column.error,
    honeycombio_column.http_route,
  ]
}

resource "honeycombio_query_annotation" "errors_by_route" {
  dataset     = var.dataset
  name        = "Errors by Route and Status Code"
  description = "Count of root spans with error=true, grouped by route and HTTP status code. Surfaces which endpoints are generating 5xx errors."
  query_id    = honeycombio_query.errors_by_route.id
}

# ============================================================
# Query: HTTP 4xx client errors by route
# ============================================================

data "honeycombio_query_specification" "client_errors_by_route" {
  calculation {
    op = "COUNT"
  }

  filter {
    column = "http.status_code"
    op     = ">="
    value  = 400
  }

  filter {
    column = "http.status_code"
    op     = "<"
    value  = 500
  }

  filter {
    column = "trace.parent_id"
    op     = "does-not-exist"
  }

  breakdowns = ["http.status_code", "http.route"]

  order {
    op    = "COUNT"
    order = "descending"
  }

  time_range = 3600
}

resource "honeycombio_query" "client_errors_by_route" {
  dataset    = var.dataset
  query_json = data.honeycombio_query_specification.client_errors_by_route.json

  depends_on = [
    honeycombio_column.http_route,
  ]
}

resource "honeycombio_query_annotation" "client_errors_by_route" {
  dataset     = var.dataset
  name        = "4xx Client Errors by Route"
  description = "HTTP 400–499 responses grouped by status code and route. High 404 rates may indicate broken links; 403s may indicate auth issues."
  query_id    = honeycombio_query.client_errors_by_route.id
}

# ============================================================
# Query: Request latency percentiles by route
# ============================================================

data "honeycombio_query_specification" "latency_by_route" {
  calculation {
    op     = "P99"
    column = "duration_ms"
  }

  calculation {
    op     = "P95"
    column = "duration_ms"
  }

  calculation {
    op     = "P50"
    column = "duration_ms"
  }

  filter {
    column = "trace.parent_id"
    op     = "does-not-exist"
  }

  filter {
    column = "http.route"
    op     = "exists"
  }

  breakdowns = ["http.route"]

  order {
    op     = "P99"
    column = "duration_ms"
    order  = "descending"
  }

  time_range = 3600
}

resource "honeycombio_query" "latency_by_route" {
  dataset    = var.dataset
  query_json = data.honeycombio_query_specification.latency_by_route.json

  depends_on = [honeycombio_column.http_route]
}

resource "honeycombio_query_annotation" "latency_by_route" {
  dataset     = var.dataset
  name        = "Request Latency (P50/P95/P99) by Route"
  description = "Tail latency per route. P99 spikes on /:slug indicate slow phrase-cloud renders; P99 spikes on /admin routes may indicate heavy query load."
  query_id    = honeycombio_query.latency_by_route.id
}

# ============================================================
# Board: whaily overview
# ============================================================

resource "honeycombio_flexible_board" "whaily" {
  name        = "whaily Overview"
  description = "Request traffic, unique visitor sessions, errors, and latency for the whaily Phoenix application."

  panel {
    type = "query"
    query_panel {
      query_id            = honeycombio_query.unique_visitor_sessions.id
      query_annotation_id = honeycombio_query_annotation.unique_visitor_sessions.id
      query_style         = "combo"
    }
  }

  panel {
    type = "query"
    query_panel {
      query_id            = honeycombio_query.requests_by_route.id
      query_annotation_id = honeycombio_query_annotation.requests_by_route.id
      query_style         = "combo"
    }
  }

  panel {
    type = "query"
    query_panel {
      query_id            = honeycombio_query.errors_by_route.id
      query_annotation_id = honeycombio_query_annotation.errors_by_route.id
      query_style         = "combo"
    }
  }

  panel {
    type = "query"
    query_panel {
      query_id            = honeycombio_query.client_errors_by_route.id
      query_annotation_id = honeycombio_query_annotation.client_errors_by_route.id
      query_style         = "combo"
    }
  }

  panel {
    type = "query"
    query_panel {
      query_id            = honeycombio_query.latency_by_route.id
      query_annotation_id = honeycombio_query_annotation.latency_by_route.id
      query_style         = "combo"
    }
  }
}
