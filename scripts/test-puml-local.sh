#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs"

get_install_hint() {
  local os_name
  os_name="$(uname -s)"

  case "$os_name" in
    Darwin)
      echo "Install with Homebrew: brew install plantuml graphviz"
      ;;
    Linux)
      echo "Install with your package manager (example Debian/Ubuntu): sudo apt-get install -y plantuml graphviz"
      ;;
    *)
      echo "Install plantuml and graphviz using your OS package manager."
      ;;
  esac
}

print_usage() {
  cat <<'EOF'
Usage:
  scripts/test-puml-local.sh [--serve]

What it does:
  1) Converts every .puml in docs/ to .svg
  2) Validates local markdown image links that point to .svg files
  3) Optionally starts Docsify for visual validation (--serve)
EOF
}

require_cmd() {
  local cmd="$1"
  local hint="$2"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[error] Missing command: $cmd"
    echo "[hint] $hint"
    exit 1
  fi
}

serve_docs() {
  if command -v docsify >/dev/null 2>&1; then
    echo "[info] Starting Docsify with global docsify command"
    docsify serve "$DOCS_DIR"
    return
  fi

  require_cmd npx "Install Node.js and npm, then try again."
  echo "[info] Starting Docsify with npx docsify-cli"
  npx docsify-cli serve "$DOCS_DIR"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  print_usage
  exit 0
fi

if [[ "${1:-}" != "" && "${1:-}" != "--serve" ]]; then
  echo "[error] Invalid argument: ${1}"
  print_usage
  exit 1
fi

if [[ ! -d "$DOCS_DIR" ]]; then
  echo "[error] docs directory was not found at: $DOCS_DIR"
  exit 1
fi

install_hint="$(get_install_hint)"
require_cmd plantuml "$install_hint"
require_cmd dot "$install_hint"

puml_files=()
while IFS= read -r -d '' file; do
  puml_files+=("$file")
done < <(find "$DOCS_DIR" -type f -name "*.puml" -print0)

if [[ ${#puml_files[@]} -eq 0 ]]; then
  echo "[info] No .puml files found in docs/."
else
  echo "[info] Converting ${#puml_files[@]} .puml file(s) to .svg"

  for file in "${puml_files[@]}"; do
    rel_file="${file#"$ROOT_DIR"/}"
    echo "  - $rel_file"
    plantuml -tsvg "$file"
  done
fi

echo "[info] Validating markdown image links that reference .svg files"

broken_links=0

while IFS= read -r md_file; do
  md_dir="$(dirname "$md_file")"

  while IFS= read -r image_link; do
    [[ -z "$image_link" ]] && continue

    if [[ "$image_link" =~ ^https?:// || "$image_link" =~ ^# ]]; then
      continue
    fi

    link_no_query="${image_link%%\?*}"
    if [[ "$link_no_query" != *.svg ]]; then
      continue
    fi

    if [[ "$link_no_query" == /* ]]; then
      target="$DOCS_DIR/${link_no_query#/}"
    else
      target="$md_dir/$link_no_query"
    fi

    if [[ ! -f "$target" ]]; then
      rel_md="${md_file#"$ROOT_DIR"/}"
      echo "[broken] $rel_md -> $image_link"
      broken_links=$((broken_links + 1))
    fi
  done < <(
    grep -oE '!\[[^]]*\]\(([^)]+)\)' "$md_file" \
      | sed -E 's/^!\[[^]]*\]\(([^)]+)\)$/\1/'
  )
done < <(find "$DOCS_DIR" -type f -name "*.md" | sort)

if [[ $broken_links -gt 0 ]]; then
  echo "[error] Found $broken_links broken .svg markdown link(s)."
  exit 2
fi

echo "[ok] Conversion finished and markdown .svg links are valid."

if [[ "${1:-}" == "--serve" ]]; then
  echo "[info] Open http://localhost:3000 to visually validate the page"
  serve_docs
fi
