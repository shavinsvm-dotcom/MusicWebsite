#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Install XcodeGen first: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

xcodebuild \
  -project MOTIF.xcodeproj \
  -scheme MOTIF \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

rm -rf Payload MOTIF.ipa
mkdir Payload
cp -R build/Build/Products/Release-iphoneos/MOTIF.app Payload/
zip -qry MOTIF.ipa Payload

echo "Built $(pwd)/MOTIF.ipa"
