#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
cd "$project_dir"

app_dir="$project_dir/dist/StudyDesk.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"

rm -rf "$app_dir"
mkdir -p "$macos_dir"
clang -fobjc-arc -O2 -mmacosx-version-min=13.0 \
    -framework Cocoa -framework CoreGraphics \
    "$project_dir/Native/main.m" \
    -o "$macos_dir/StudyDesk"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
xattr -cr "$app_dir"
echo "$app_dir"
