#!/usr/bin/env python3
"""Builds the MilkDrop preset pack: build/plugins/MacAmp MilkDrop Presets.macampplugin and, for the site and the
release, build/MacAmp-MilkDrop-Presets-CreamOfTheCrop.zip (named as MacAmp-AVS-Presets-Winamp295.zip).

projectM's default pack, "Cream of the Crop" by ISOSCELES (github.com/projectM-visualizer/presets-cream-of-the-crop):
9,795 presets in theme folders, public domain by its LICENSE.md, which goes into the pack with the README.
Taken from a local copy of that repository, by default the one MacAmp reads (~/Library/Application Support/MacAmp/Milkdrop).

Usage: python3 scripts/build_milkdrop_presets.py [path to presets-cream-of-the-crop]
"""
import os, plistlib, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Library/Application Support/MacAmp/Milkdrop')
OUT = os.path.join(ROOT, 'build', 'plugins')
PACK = os.path.join(OUT, 'MacAmp MilkDrop Presets.macampplugin')
ARCHIVE = os.path.join(ROOT, 'build', 'MacAmp-MilkDrop-Presets-CreamOfTheCrop.zip')
TITLE_MARK = 'Cream of the Crop'
EXPECTED = 9795
NOTES = ['LICENSE.md', 'README.md']

readme = open(os.path.join(SOURCE, 'README.md'), encoding='utf-8').read()
if TITLE_MARK not in readme:
    sys.exit(f'{SOURCE} is not the {TITLE_MARK} pack')
presets = [os.path.join(d, f) for d, _, files in os.walk(SOURCE) for f in files if f.lower().endswith('.milk')]
if len(presets) != EXPECTED:
    sys.exit(f'expected {EXPECTED} presets, found {len(presets)} (presets added to the folder by hand?)')

shutil.rmtree(PACK, ignore_errors=True)
resources = os.path.join(PACK, 'Contents', 'Resources')
for path in presets:
    target = os.path.join(resources, os.path.relpath(path, SOURCE))
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile(path, target)
for note in NOTES:
    shutil.copyfile(os.path.join(SOURCE, note), os.path.join(resources, note))

with open(os.path.join(PACK, 'Contents', 'Info.plist'), 'wb') as f:
    plistlib.dump({'CFBundleIdentifier': 'alexrel.MacAmp.milkdrop-presets.cream-of-the-crop',
                   'CFBundleName': 'MacAmp MilkDrop Presets',
                   'MacAmpPluginKind': 'milkdrop-presets',
                   'MacAmpPluginTitle': f'MilkDrop presets: {TITLE_MARK} ({EXPECTED:,})'}, f)
if os.path.exists(ARCHIVE):
    os.remove(ARCHIVE)
subprocess.run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--noacl', '--keepParent', PACK, ARCHIVE], check=True)
print(f'{len(presets)} presets -> {PACK}\n{ARCHIVE}')
