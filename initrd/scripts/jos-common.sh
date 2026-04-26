#!/bin/bash
set -e

JOS_ERROR_LOG="/tmp/jos_error.log"

log() {
  echo "JOS: $*"
}

err() {
  echo "JOS-ERROR: $*" | tee -a "$JOS_ERROR_LOG" >&2
}

die() {
  err "$@"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

jos_load_fog_config() {
  # The standards require referencing $FOG_CONFIG_FILE (no hardcoded keys).
  # Format is simple shell variables, for example:
  #   FOG_SERVER="fog.example.org"
  #   FOG_API_KEY="..."
  #   FOG_USER_TOKEN="..."
  : "${FOG_CONFIG_FILE:=/etc/fog/jos.conf}"
  if [[ ! -f "$FOG_CONFIG_FILE" ]]; then
    die "FOG config file not found: $FOG_CONFIG_FILE"
  fi
  # shellcheck disable=SC1090
  source "$FOG_CONFIG_FILE"

  # If FOG_SERVER isn't explicitly set, prefer DHCP "NEXT SERVER" (siaddr).
  if [[ -z "${FOG_SERVER:-}" && -f /tmp/jos-next-server ]]; then
    FOG_SERVER="$(cat /tmp/jos-next-server 2>/dev/null || true)"
  fi

  : "${FOG_SERVER:?FOG_SERVER not set in $FOG_CONFIG_FILE (or via DHCP NEXT SERVER)}"
  : "${FOG_API_KEY:?FOG_API_KEY not set in $FOG_CONFIG_FILE}"
  : "${FOG_USER_TOKEN:?FOG_USER_TOKEN not set in $FOG_CONFIG_FILE}"
}

jos_curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1:-}"

  local curl_bin="/tools/curl"
  [[ -x "$curl_bin" ]] || curl_bin=""

  if [[ -n "$curl_bin" ]]; then
    if [[ -n "$data" ]]; then
      "$curl_bin" -fsS -X "$method" "$url" \
        -H "Content-Type: application/json" \
        -H "fog-api-token: ${FOG_API_KEY}" \
        -H "fog-user-token: ${FOG_USER_TOKEN}" \
        --data "$data"
    else
      "$curl_bin" -fsS -X "$method" "$url" \
        -H "fog-api-token: ${FOG_API_KEY}" \
        -H "fog-user-token: ${FOG_USER_TOKEN}"
    fi
    return 0
  fi

  # Fallback: BusyBox wget (keeps initrd workable even if curl isn't present).
  # Note: BusyBox wget doesn't support all curl features; this is best-effort.
  local wget_bin="wget"
  require_cmd "$wget_bin"

  local tmp_body="/tmp/jos_http_body.$$"
  local tmp_hdr="/tmp/jos_http_hdr.$$"
  rm -f "$tmp_body" "$tmp_hdr" || true

  local headers=(
    "--header=fog-api-token: ${FOG_API_KEY}"
    "--header=fog-user-token: ${FOG_USER_TOKEN}"
  )
  if [[ -n "$data" ]]; then
    headers+=("--header=Content-Type: application/json")
    # BusyBox wget uses --post-data for POST; for PUT/DELETE we still try --method if present.
    # BusyBox wget versions differ; prefer --method/--body-data if available,
    # else fall back to POST-only --post-data.
    if "$wget_bin" --help 2>&1 | grep -q -- '--method' && "$wget_bin" --help 2>&1 | grep -q -- '--body-data'; then
      "$wget_bin" -qO "$tmp_body" -S --server-response \
        --method="$method" \
        "${headers[@]}" \
        --body-data="$data" \
        "$url" 2>"$tmp_hdr" || die "HTTP ${method} failed (wget)"
    else
      if [[ "$method" != "POST" ]]; then
        die "wget fallback lacks --method; cannot ${method} ${url}"
      fi
      "$wget_bin" -qO "$tmp_body" -S --server-response \
        "${headers[@]}" \
        --post-data="$data" \
        "$url" 2>"$tmp_hdr" || die "HTTP POST failed (wget)"
    fi
  else
    "$wget_bin" -qO "$tmp_body" -S --server-response \
      "${headers[@]}" \
      "$url" 2>"$tmp_hdr" || die "HTTP GET failed (wget)"
  fi

  cat "$tmp_body"
  rm -f "$tmp_body" "$tmp_hdr" || true
}

