#!/usr/bin/env python3
"""Validate bundled updater configuration; --distribution additionally checks Gatekeeper."""
import argparse
import base64
import plistlib
import subprocess
from pathlib import Path
from urllib.parse import urlparse

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('--distribution', action='store_true')
args = parser.parse_args()
info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.photoshelf.local', 'Do not change the existing library identity'
assert int(info['CFBundleVersion']) > 1
assert urlparse(info['SUFeedURL']).scheme == 'https'
assert len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32
assert info.get('SUEnableInstallerLauncherService') is True
assert info.get('SUEnableDownloaderService') is True
framework = args.app / 'Contents/Frameworks/Sparkle.framework'
assert framework.exists(), 'Sparkle must be embedded, not only linked'
for path in ['XPCServices/Installer.xpc', 'XPCServices/Downloader.xpc', 'Updater.app', 'Autoupdate']:
    assert (framework / 'Versions/B' / path).exists(), path
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.app)], check=True)
if args.distribution:
    subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(args.app)], check=True)
    subprocess.run(['xcrun', 'stapler', 'validate', str(args.app)], check=True)
print('Updater configuration and signature structure OK' + ('; distribution checks passed' if args.distribution else '; NOT a notarization check'))
