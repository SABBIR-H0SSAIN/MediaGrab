#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"
test_cases="${YOUTUBE_TEST_CASES:-39h7ZJbRcsw|360p,39h7ZJbRcsw|720p|pause,39h7ZJbRcsw|1080p|403,39h7ZJbRcsw|1440p|normal|av01,39h7ZJbRcsw|2160p|normal|vp9,-hwMHF1rXvU|360p|expired,-hwMHF1rXvU|480p|-|avc,-hwMHF1rXvU|720p|cancel|av01,-hwMHF1rXvU|1080p|normal|vp9,-hwMHF1rXvU|1440p|normal|av01,aqz-KE-bpKQ|720p60,aqz-KE-bpKQ|1080p60}"
flutter build apk --release -t "${YOUTUBE_PROBE_ENTRYPOINT:-tool/youtube_device_probe.dart}" "--dart-define=YOUTUBE_TEST_CASES=$test_cases"
if [[ "${YOUTUBE_BUILD_ONLY:-0}" == "1" ]]; then
    exit 0
fi
adb_bin="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
"$adb_bin" install -r build/app/outputs/flutter-apk/app-release.apk
"$adb_bin" shell am start -n com.mediagrab.mediagrab/.MainActivity
# Test results are persisted in Android/data/com.mediagrab.mediagrab/files/youtube-mission-tests.
# Restore the normal app afterwards: flutter build apk --release, then adb install -r.
