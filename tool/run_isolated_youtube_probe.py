"""Build the real device probe under a separate package, preserving the main app."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

source = Path(__file__).resolve().parent.parent
destination = Path('/private/tmp/mediagrab-youtube-probe')
destination.mkdir(exist_ok=True)
for name in ['lib', 'assets', 'tool', 'android']:
    shutil.copytree(source / name, destination / name, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('build', '.gradle', '.cxx'))
for name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']:
    if (source / name).exists():
        shutil.copy2(source / name, destination / name)
gradle = destination / 'android/app/build.gradle.kts'
gradle.write_text(gradle.read_text().replace(
    'applicationId = "com.mediagrab.mediagrab"',
    'applicationId = "com.mediagrab.mediagrab.youtubeprobe"'))
manifest = destination / 'android/app/src/main/AndroidManifest.xml'
manifest.write_text(manifest.read_text().replace(
    'android:label="MediaGrab"', 'android:label="MediaGrab YouTube Tests"'))
runner = destination / 'tool/run_youtube_device_probe.sh'
runner.write_text(runner.read_text().replace(
    'com.mediagrab.mediagrab/.MainActivity',
    'com.mediagrab.mediagrab.youtubeprobe/com.mediagrab.mediagrab.MainActivity'))
(destination / 'source-sha256.json').write_text(json.dumps({
    str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in (source / 'lib').rglob('*.dart')
}, indent=2))
subprocess.run(['bash', str(runner)], check=True)
