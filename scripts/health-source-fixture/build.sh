#!/bin/zsh
set -eu
repo_root=${0:A:h:h:h}
fixture_root=/tmp/LumenBatch43HealthSource
app_path="$fixture_root/LumenHealthSourceFixture.app"
mkdir -p "$app_path" "$fixture_root/ModuleCache"
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
cat > "$app_path/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.dbakp.lumen.fixture.health-source</string>
<key>CFBundleExecutable</key><string>LumenHealthSourceFixture</string>
<key>CFBundleName</key><string>Lumen Health Source Fixture</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleShortVersionString</key><string>4.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>MinimumOSVersion</key><string>18.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>NSHealthShareUsageDescription</key><string>Read only tagged simulator test samples to verify their source and cleanup.</string>
<key>NSHealthUpdateUsageDescription</key><string>Create and remove tagged simulator test samples for Lumen data checks.</string>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
cat > "$fixture_root/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST
cat > "$fixture_root/simulated-entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>3UZ4C73FM2.com.dbakp.lumen.fixture.health-source</string>
<key>com.apple.developer.healthkit</key><true/>
</dict></plist>
PLIST
xcrun swiftc -parse-as-library -swift-version 5 -sdk "$sdk_path" -target arm64-apple-ios18.0-simulator \
  -module-cache-path "$fixture_root/ModuleCache" -framework SwiftUI -framework HealthKit \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$fixture_root/simulated-entitlements.plist" \
  "$repo_root/scripts/health-source-fixture/HealthSourceFixture.swift" \
  "$repo_root/scripts/health-source-fixture/LumenOwnedInspection.swift" -o "$app_path/LumenHealthSourceFixture"
# Match Xcode: simulated entitlements are embedded in __TEXT; the ad-hoc
# simulator signature has empty entitlements.
codesign --force --sign - --entitlements "$fixture_root/entitlements.plist" "$app_path"
codesign --verify --strict "$app_path"
echo "$app_path"
