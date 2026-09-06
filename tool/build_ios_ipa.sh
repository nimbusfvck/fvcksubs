#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly APP_DIR="$REPO_ROOT/apps/app"
readonly ARCHIVE_PATH="$APP_DIR/build/ios/archive/Runner.xcarchive"
readonly APP_PATH="$ARCHIVE_PATH/Products/Applications/Runner.app"
readonly IPA_DIR="$APP_DIR/build/ios/ipa"

skip_pub_get=false
build_name=''
build_number=''

usage() {
  cat <<'EOF'
Usage: tool/build_ios_ipa.sh [options]

Build an unsigned Release IPA from the iOS archive.

Options:
  --build-name <version>    Override the iOS version number
  --build-number <number>   Override the iOS build number
  --skip-pub-get            Do not run flutter pub get
  -h, --help                Show this help
EOF
}

while (($# > 0)); do
  case "$1" in
    --build-name)
      (($# >= 2)) || { echo 'Missing value for --build-name' >&2; exit 2; }
      build_name="$2"
      shift 2
      ;;
    --build-number)
      (($# >= 2)) || { echo 'Missing value for --build-number' >&2; exit 2; }
      build_number="$2"
      shift 2
      ;;
    --skip-pub-get)
      skip_pub_get=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != 'Darwin' ]]; then
  echo 'This script must run on macOS.' >&2
  exit 1
fi

for command_name in flutter ditto zip unzip grep; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 1
  fi
done

cd "$APP_DIR"

if [[ "$skip_pub_get" == false ]]; then
  flutter pub get
fi

project_version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)"
test -n "$project_version" || {
  echo 'Could not read the app version from pubspec.yaml' >&2
  exit 1
}

version_name="${build_name:-${project_version%%+*}}"
default_build_number='1'
if [[ "$project_version" == *'+'* ]]; then
  default_build_number="${project_version##*+}"
fi
build_number="${build_number:-$default_build_number}"

[[ "$version_name" =~ ^[0-9]+(\.[0-9]+)*$ ]] || {
  echo "Invalid build name: $version_name" >&2
  exit 2
}
[[ "$build_number" =~ ^[0-9]+$ ]] || {
  echo "Invalid build number: $build_number" >&2
  exit 2
}

readonly IPA_PATH="$IPA_DIR/fvcksubs-v${version_name}-build${build_number}-unsigned.ipa"

build_arguments=(--release --no-codesign)
if [[ -n "$build_name" ]]; then
  build_arguments+=(--build-name "$build_name")
fi
if [[ -n "$build_number" ]]; then
  build_arguments+=(--build-number "$build_number")
fi

flutter build ipa "${build_arguments[@]}"

test -d "$APP_PATH" || {
  echo "Release app not found in $ARCHIVE_PATH" >&2
  exit 1
}

stage_dir="$(mktemp -d -t fvcksubs-ipa.XXXXXX)"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT

mkdir -p "$IPA_DIR" "$stage_dir/Payload"
ditto "$APP_PATH" "$stage_dir/Payload/Runner.app"
rm -f "$IPA_PATH"

(
  cd "$stage_dir"
  zip -qry "$IPA_PATH" Payload
)

contents_path="$stage_dir/contents.txt"
unzip -l "$IPA_PATH" > "$contents_path"
grep -q 'Payload/Runner.app/' "$contents_path" || {
  echo "Invalid IPA structure: $IPA_PATH" >&2
  exit 1
}

echo "Unsigned IPA created: $IPA_PATH"
