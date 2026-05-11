#!/bin/sh
# shellcheck shell=bash
# Shared helpers for JOS initramfs scripts (sourced — do not use `exec` here).
set -e

JOS_ERROR_LOG="/tmp/jos_error.log"

log() {
  echo "[JOS][$(date +%H:%M:%S)] $*"
}

err() {
  local _msg="[JOS-ERROR][$(date +%H:%M:%S)] $*"
  echo "$_msg"
  echo "$_msg" >>"$JOS_ERROR_LOG" 2>/dev/null || true
}

die() {
  err "$@"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

# --- FOG base URL (HTTPS supported for production FOG installs) ---
jos_fog_base_url() {
  local scheme="http"
  case "${FOG_USE_SSL:-0}" in
    1|true|yes|on) scheme="https" ;;
  esac
  printf '%s://%s/fog' "$scheme" "${FOG_SERVER:?}"
}

# Minimal path encoding for search terms (service tags are usually alphanumeric).
jos_fog_uri_escape_path() {
  printf '%s' "$1" | sed 's/\r//g;s/%/%25/g;s/ /%20/g;s/#/%23/g;s/?/%3F/g;s/&/%26/g;s/+/%2B/g;s/\[/%5B/g;s/\]/%5D/g'
}

# --- FOG JSON (best-effort without jq; responses wrap under "data" on some endpoints) ---
jos_fog_extract_json_id() {
  local j="$1"
  local id=""
  id="$(echo "$j" | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*{[[:space:]]*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  if [[ -z "$id" ]]; then
    id="$(echo "$j" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  fi
  printf '%s' "$id"
}

jos_fog_json_has_entity_id() {
  [[ -n "$(jos_fog_extract_json_id "${1:-}")" ]]
}

# GET /fog/host/search/:item returns { count, hosts: [ { id, ...}, ... ] }
jos_fog_first_host_id_from_search() {
  local j="$1"
  echo "$j" | tr -d '\r\n' | sed -n 's/.*"hosts"[[:space:]]*:[[:space:]]*\[[[:space:]]*{[[:space:]]*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -c 32
}

jos_fog_resolve_host_id() {
  local serial="$1"
  local base enc search_json hid
  base="$(jos_fog_base_url)"
  enc="$(jos_fog_uri_escape_path "$serial")"
  search_json="$(jos_curl_json GET "${base}/host/search/${enc}" 2>/dev/null || true)"
  hid="$(jos_fog_first_host_id_from_search "$search_json")"
  printf '%s' "$hid"
}

jos_fog_extract_inventory_id_from_host_json() {
  local j="$1"
  local flat
  flat="$(echo "$j" | tr -d '\r\n')"
  if echo "$flat" | grep -q '"inventory"[[:space:]]*:[[:space:]]*null'; then
    printf ''
    return 0
  fi
  echo "$flat" | sed -n 's/.*"inventory"[[:space:]]*:[[:space:]]*{.*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -c 32
}

jos_fog_extract_task_id_from_host_json() {
  local j="$1"
  local flat
  flat="$(echo "$j" | tr -d '\r\n')"
  if echo "$flat" | grep -qE '"task"[[:space:]]*:[[:space:]]*(null|false)'; then
    printf ''
    return 0
  fi
  echo "$flat" | sed -n 's/.*"task"[[:space:]]*:[[:space:]]*{.*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -c 32
}

jos_load_fog_config() {
  # Load $FOG_CONFIG_FILE (no hardcoded secrets).
  : "${FOG_CONFIG_FILE:=/etc/fog/jos.conf}"
  if [[ ! -f "$FOG_CONFIG_FILE" ]]; then
    die "FOG config file not found: $FOG_CONFIG_FILE"
  fi
  # shellcheck disable=SC1090
  # shellcheck disable=SC1090
  . "$FOG_CONFIG_FILE"

  if [[ -z "${FOG_SERVER:-}" && -f /tmp/jos-next-server ]]; then
    FOG_SERVER="$(cat /tmp/jos-next-server 2>/dev/null || true)"
  fi

  : "${FOG_SERVER:?FOG_SERVER not set in $FOG_CONFIG_FILE (or via DHCP NEXT SERVER)}"
  : "${FOG_API_KEY:?FOG_API_KEY not set in $FOG_CONFIG_FILE}"
  : "${FOG_USER_TOKEN:?FOG_USER_TOKEN not set in $FOG_CONFIG_FILE}"

  : "${FOG_USE_SSL:=0}"
  : "${FOG_SSL_INSECURE:=0}"

  jos_fog_ensure_profile || true
}

# --- FOG version probe & API path selection (cached in /tmp per boot) ---
JOS_FOG_PROFILE_FILE="/tmp/jos-fog-profile.env"

jos_fog_http_get_plain() {
  local url="$1"
  local curl_bin="/tools/curl"
  [ -x "$curl_bin" ] || curl_bin=""
  [ -n "$curl_bin" ] || return 1
  local tls_k="" tls_cacert=""
  [ "${FOG_SSL_INSECURE:-0}" = "1" ] && tls_k="-k"
  [ -n "${FOG_CA_BUNDLE:-}" ] && [ -f "${FOG_CA_BUNDLE}" ] && tls_cacert="--cacert ${FOG_CA_BUNDLE}"
  # shellcheck disable=SC2086
  "${curl_bin}" $tls_k $tls_cacert -fsS "$url" 2>/dev/null || return 1
}

jos_fog_semver_to_sortkey() {
  local v="$1"
  [[ -z "$v" ]] && echo 0 && return 0
  echo "$v" | awk -F. 'NF>=3 { printf "%d\n", ($1+0)*1000000+($2+0)*1000+($3+0); next } { print "0\n" }'
}

jos_fog_extract_version_from_html() {
  local html="$1"
  local line v
  line="$(echo "$html" | tr '\n' ' ')"
  v="$(echo "$line" | grep -oiE 'FOG[^<]{0,160}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
  [[ -n "$v" ]] && { echo "$v"; return 0; }
  v="$(echo "$line" | grep -oiE '[Vv]ersion[[:space:]][0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
  [[ -n "$v" ]] && { echo "$v"; return 0; }
  echo ""
}

jos_fog_host_create_paths_for_key() {
  local sk="$1"
  case "${JOS_FOG_API_STYLE:-auto}" in
    modern) echo "/host/create /host/new /host"; return ;;
    legacy) echo "/host /host/create /host/new"; return ;;
  esac
  if [[ "$sk" -eq 0 ]]; then
    echo "/host/create /host/new /host"
    return
  fi
  if [[ "$sk" -lt 1005000 ]]; then
    echo "/host /host/create /host/new"
    return
  fi
  echo "/host/create /host/new /host"
}

jos_fog_inventory_create_paths_for_key() {
  local sk="$1"
  case "${JOS_FOG_API_STYLE:-auto}" in
    modern) echo "/inventory/create /inventory/new /inventory"; return ;;
    legacy) echo "/inventory /inventory/create /inventory/new"; return ;;
  esac
  if [[ "$sk" -eq 0 ]]; then
    echo "/inventory/create /inventory/new /inventory"
    return
  fi
  if [[ "$sk" -lt 1005000 ]]; then
    echo "/inventory /inventory/create /inventory/new"
    return
  fi
  echo "/inventory/create /inventory/new /inventory"
}

jos_fog_mc_session_paths_for_key() {
  local sk="$1"
  case "${JOS_FOG_API_STYLE:-auto}" in
    modern) echo "/multicastsession/create /multicastsession/new /multicastsession"; return ;;
    legacy) echo "/multicastsession /multicastsession/create /multicastsession/new"; return ;;
  esac
  if [[ "$sk" -eq 0 ]]; then
    echo "/multicastsession/create /multicastsession/new /multicastsession"
    return
  fi
  if [[ "$sk" -lt 1005000 ]]; then
    echo "/multicastsession /multicastsession/create /multicastsession/new"
    return
  fi
  echo "/multicastsession/create /multicastsession/new /multicastsession"
}

jos_fog_mc_assoc_paths_for_key() {
  local sk="$1"
  case "${JOS_FOG_API_STYLE:-auto}" in
    modern) echo "/multicastsessionassociation/create /multicastsessionassociation/new /multicastsessionassociation"; return ;;
    legacy) echo "/multicastsessionassociation /multicastsessionassociation/create /multicastsessionassociation/new"; return ;;
  esac
  if [[ "$sk" -eq 0 ]]; then
    echo "/multicastsessionassociation/create /multicastsessionassociation/new /multicastsessionassociation"
    return
  fi
  if [[ "$sk" -lt 1005000 ]]; then
    echo "/multicastsessionassociation /multicastsessionassociation/create /multicastsessionassociation/new"
    return
  fi
  echo "/multicastsessionassociation/create /multicastsessionassociation/new /multicastsessionassociation"
}

jos_fog_default_modules_json_for_key() {
  local sk="$1"
  if [[ "$sk" -lt 1005000 && "$sk" -gt 0 ]]; then
    printf '%s' '["7","9","13"]'
    return 0
  fi
  printf '%s' '["7","9","13","6","11","2","12"]'
}

jos_fog_write_profile_file() {
  {
    printf 'export FOG_VERSION_RAW="%s"\n'          "$FOG_VERSION_RAW"
    printf 'export FOG_VER_SORTKEY="%s"\n'          "$FOG_VER_SORTKEY"
    printf 'export JOS_FOG_HOST_CREATE_PATHS="%s"\n' "$JOS_FOG_HOST_CREATE_PATHS"
    printf 'export JOS_FOG_INV_CREATE_PATHS="%s"\n'  "$JOS_FOG_INV_CREATE_PATHS"
    printf 'export JOS_FOG_MC_SESSION_PATHS="%s"\n'  "$JOS_FOG_MC_SESSION_PATHS"
    printf 'export JOS_FOG_MC_ASSOC_PATHS="%s"\n'    "$JOS_FOG_MC_ASSOC_PATHS"
  } >"$JOS_FOG_PROFILE_FILE"
}

jos_fog_apply_default_profile() {
  export FOG_VERSION_RAW="unknown"
  export FOG_VER_SORTKEY="0"
  export JOS_FOG_HOST_CREATE_PATHS
  export JOS_FOG_INV_CREATE_PATHS
  export JOS_FOG_MC_SESSION_PATHS
  export JOS_FOG_MC_ASSOC_PATHS
  JOS_FOG_HOST_CREATE_PATHS="$(jos_fog_host_create_paths_for_key 0)"
  JOS_FOG_INV_CREATE_PATHS="$(jos_fog_inventory_create_paths_for_key 0)"
  JOS_FOG_MC_SESSION_PATHS="$(jos_fog_mc_session_paths_for_key 0)"
  JOS_FOG_MC_ASSOC_PATHS="$(jos_fog_mc_assoc_paths_for_key 0)"
  jos_fog_write_profile_file
}

jos_fog_probe_and_save() {
  local base ver raw html sk
  base="$(jos_fog_base_url)"
  raw="${FOG_VERSION_OVERRIDE:-}"
  ver=""

  if [[ -n "$raw" ]]; then
    ver="$raw"
    log "FOG: using FOG_VERSION_OVERRIDE=${ver}"
  else
    html="$(jos_fog_http_get_plain "${base}/management/index.php" || true)"
    ver="$(jos_fog_extract_version_from_html "$html")"
    [[ -n "$ver" ]] && log "FOG: detected server version from web UI markup: ${ver}"
  fi

  sk="$(jos_fog_semver_to_sortkey "$ver")"
  [[ -z "$sk" ]] && sk=0

  export FOG_VER_SORTKEY="$sk"
  if [[ -n "$ver" ]]; then
    export FOG_VERSION_RAW="$ver"
  else
    export FOG_VERSION_RAW="unknown"
    log "FOG: version probe found no semver (login HTML may differ); using fallback API path order"
  fi
  export JOS_FOG_HOST_CREATE_PATHS
  export JOS_FOG_INV_CREATE_PATHS
  export JOS_FOG_MC_SESSION_PATHS
  export JOS_FOG_MC_ASSOC_PATHS
  JOS_FOG_HOST_CREATE_PATHS="$(jos_fog_host_create_paths_for_key "$sk")"
  JOS_FOG_INV_CREATE_PATHS="$(jos_fog_inventory_create_paths_for_key "$sk")"
  JOS_FOG_MC_SESSION_PATHS="$(jos_fog_mc_session_paths_for_key "$sk")"
  JOS_FOG_MC_ASSOC_PATHS="$(jos_fog_mc_assoc_paths_for_key "$sk")"

  jos_fog_write_profile_file
}

jos_fog_ensure_profile() {
  case "${JOS_FOG_SKIP_VERSION_PROBE:-0}" in 1|true|yes|on)
    jos_fog_apply_default_profile
    . "$JOS_FOG_PROFILE_FILE"
    return 0
  esac
  if [ -f "$JOS_FOG_PROFILE_FILE" ] && [ "${JOS_FOG_FORCE_PROBE:-0}" != "1" ]; then
    . "$JOS_FOG_PROFILE_FILE"
    return 0
  fi
  jos_fog_probe_and_save || jos_fog_apply_default_profile
  # shellcheck disable=SC1090
  . "$JOS_FOG_PROFILE_FILE"
}

# POST JSON to first path in list that returns an entity id (FOG create routes).
jos_fog_api_post_first_id() {
  local base="$1"
  local path_list="$2"
  local payload="$3"
  local p result=""
  for p in $path_list; do
    result="$(jos_curl_json POST "${base}${p}" "${payload}" 2>/dev/null || true)"
    if jos_fog_json_has_entity_id "$result"; then
      printf '%s\n' "$result"
      return 0
    fi
  done
  printf '%s\n' "$result"
  return 1
}

# POST until HTTP success — inventory create (body may be empty JSON).
jos_fog_api_post_first_ok() {
  local base="$1"
  local path_list="$2"
  local payload="$3"
  local p
  for p in $path_list; do
    if jos_curl_json POST "${base}${p}" "${payload}" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# PUT inventory: try …/edit then …/update (FOG router accepts both names).
jos_fog_api_put_inventory() {
  local base="$1"
  local inv_id="$2"
  local payload="$3"
  if jos_curl_json PUT "${base}/inventory/${inv_id}/edit" "${payload}" >/dev/null 2>&1; then
    return 0
  fi
  jos_curl_json PUT "${base}/inventory/${inv_id}/update" "${payload}" >/dev/null 2>&1
}

jos_curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1:-}"

  local curl_bin="/tools/curl"
  [ -x "$curl_bin" ] || curl_bin=""

  if [ -n "$curl_bin" ]; then
    local tls_k="" tls_cacert=""
    [ "${FOG_SSL_INSECURE:-0}" = "1" ] && tls_k="-k"
    [ -n "${FOG_CA_BUNDLE:-}" ] && [ -f "${FOG_CA_BUNDLE}" ] && tls_cacert="--cacert ${FOG_CA_BUNDLE}"
    if [ -n "$data" ]; then
      # shellcheck disable=SC2086
      "${curl_bin}" $tls_k $tls_cacert -fsS -X "$method" "$url" \
        -H "Content-Type: application/json" \
        -H "fog-api-token: ${FOG_API_KEY}" \
        -H "fog-user-token: ${FOG_USER_TOKEN}" \
        --data "$data"
    else
      # shellcheck disable=SC2086
      "${curl_bin}" $tls_k $tls_cacert -fsS -X "$method" "$url" \
        -H "fog-api-token: ${FOG_API_KEY}" \
        -H "fog-user-token: ${FOG_USER_TOKEN}"
    fi
    return 0
  fi

  # Fallback: BusyBox wget (no TLS flag support — prefer bundled /tools/curl).
  local wget_bin="wget"
  require_cmd "$wget_bin"

  local tmp_body="/tmp/jos_http_body.$$"
  local tmp_hdr="/tmp/jos_http_hdr.$$"
  rm -f "$tmp_body" "$tmp_hdr" || true

  local hdr_api="--header=fog-api-token: ${FOG_API_KEY}"
  local hdr_user="--header=fog-user-token: ${FOG_USER_TOKEN}"

  if [ -n "$data" ]; then
    if "$wget_bin" --help 2>&1 | grep -q -- '--method' && "$wget_bin" --help 2>&1 | grep -q -- '--body-data'; then
      "$wget_bin" -qO "$tmp_body" -S --server-response \
        --method="$method" \
        "$hdr_api" "$hdr_user" \
        "--header=Content-Type: application/json" \
        --body-data="$data" \
        "$url" 2>"$tmp_hdr" || die "HTTP ${method} failed (wget)"
    else
      [ "$method" = "POST" ] || die "wget fallback lacks --method; cannot ${method} ${url}"
      "$wget_bin" -qO "$tmp_body" -S --server-response \
        "$hdr_api" "$hdr_user" \
        "--header=Content-Type: application/json" \
        --post-data="$data" \
        "$url" 2>"$tmp_hdr" || die "HTTP POST failed (wget)"
    fi
  else
    "$wget_bin" -qO "$tmp_body" -S --server-response \
      "$hdr_api" "$hdr_user" \
      "$url" 2>"$tmp_hdr" || die "HTTP GET failed (wget)"
  fi

  cat "$tmp_body"
  rm -f "$tmp_body" "$tmp_hdr" || true
}

# --- jq helpers (optional but recommended; bundled into initrd by build scripts) ---
jos_jq_bin() {
  if [[ -x /tools/jq ]]; then
    echo "/tools/jq"
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    command -v jq
    return 0
  fi
  echo ""
  return 1
}

# Unwrap FOG API envelopes: prefer `.data` when present.
jos_fog_json_core() {
  local json="$1"
  local jb
  jb="$(jos_jq_bin || true)"
  [[ -n "$jb" ]] || { printf '%s' "$json"; return 0; }
  printf '%s' "$json" | "$jb" -c 'if type == "object" and has("data") then .data else . end' 2>/dev/null || printf '%s' "$json"
}

jos_fog_jq() {
  local json="$1"
  local query="$2"
  local jb
  jb="$(jos_jq_bin || true)"
  [[ -n "$jb" ]] || return 1
  printf '%s' "$json" | "$jb" -r "$query" 2>/dev/null
}

jos_fog_get_image_json() {
  local image_id="$1"
  local base url
  base="$(jos_fog_base_url)"
  url="${base}/image/${image_id}"
  jos_curl_json GET "$url" 2>/dev/null || true
}

# Tell FOG the task has started (moves queued → in-progress in the FOG UI).
jos_fog_task_checkin() {
  local task_id="$1"
  [[ -n "$task_id" ]] || return 0
  local base
  base="$(jos_fog_base_url)"
  jos_curl_json PUT "${base}/task/${task_id}" '{"stateID":2}' >/dev/null 2>&1 || \
    log "FOG: task checkin non-fatal (task_id=${task_id})"
}

# Tell FOG the task is done — DELETE removes it from the queue so next boot is clean.
jos_fog_task_done() {
  local task_id="$1"
  [[ -n "$task_id" ]] || return 0
  local base
  base="$(jos_fog_base_url)"
  if ! jos_curl_json DELETE "${base}/task/${task_id}" >/dev/null 2>&1; then
    jos_curl_json PUT "${base}/task/${task_id}" '{"stateID":3}' >/dev/null 2>&1 || \
      log "FOG: task done non-fatal (task_id=${task_id})"
  fi
}
