#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(/usr/bin/dirname "$0")/.." && pwd)
build_dir="$project_dir/build"
app_name="剪贴板历史.app"
temp_dir=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)
module_cache="${temp_dir%/}/local.clipboard-history-module-cache"
sdk_path=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
architecture=$(/usr/bin/uname -m)
minimum_macos=$(/usr/bin/plutil -extract LSMinimumSystemVersion raw "$project_dir/Resources/Info.plist")

/bin/mkdir -p "$build_dir" "$module_cache"
stage_dir=$(/usr/bin/mktemp -d "$build_dir/.staging.XXXXXXXX")
trap '/bin/rm -rf -- "$stage_dir"' EXIT
trap 'exit 1' HUP INT TERM

contents="$stage_dir/$app_name/Contents"
/bin/mkdir -p "$contents/MacOS"
/bin/cp "$project_dir/Resources/Info.plist" "$contents/Info.plist"
/usr/bin/xcrun --sdk macosx swiftc \
    -swift-version 6 -warnings-as-errors \
    -sdk "$sdk_path" -target "$architecture-apple-macosx$minimum_macos" \
    -module-cache-path "$module_cache" \
    "$project_dir"/Sources/ClipboardHistory/*.swift \
    -o "$contents/MacOS/ClipboardHistory"

/usr/bin/codesign --sign - "$stage_dir/$app_name"
/usr/bin/ditto "$stage_dir/$app_name" "$build_dir/$app_name"
/usr/bin/codesign --verify --strict "$build_dir/$app_name"
printf '%s\n' "$build_dir/$app_name"
