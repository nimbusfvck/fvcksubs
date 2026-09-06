#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
app_dir="$repo_dir/apps/app"
env_file="$app_dir/.env"
env_example="$app_dir/.env.example"
created_env_file=false

if [[ ! -f "$env_file" ]]; then
  if [[ -n "${OPENSUBTITLES_API_KEY:-}" ]]; then
    printf 'OPENSUBTITLES_API_KEY=%s\n' "$OPENSUBTITLES_API_KEY" > "$env_file"
  else
    cp "$env_example" "$env_file"
  fi
  created_env_file=true
fi

cleanup() {
  if [[ "$created_env_file" == true ]]; then
    rm -f "$env_file"
  fi
}
trap cleanup EXIT

cd "$app_dir"
dart run build_runner build
