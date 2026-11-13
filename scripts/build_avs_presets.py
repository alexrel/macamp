#!/usr/bin/env python3
"""Builds the Winamp 2.95 AVS preset pack: build/plugins/Winamp 2.95 AVS Presets.macampplugin (+ .zip for the site).

The 112 presets Winamp 2.95 installs into Plugins\\avs\\newpicks, taken from the installer as extracted by
scripts/extract_nsis1.py into docs/winamp295-extracted/raw (local only, docs/ is not in git). The script header
(000_bin.dat) lists the file names in the order the data blocks follow: 029_bin.dat onwards, alphabetical.
mig-new4.avs has no block of its own: it is byte for byte vis_avs.dat (027), stored once by the installer.

Usage: python3 scripts/build_avs_presets.py
"""
import os, plistlib, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'docs', 'winamp295-extracted', 'raw')
OUT = os.path.join(ROOT, 'build', 'plugins')
PACK = os.path.join(OUT, 'Winamp 2.95 AVS Presets.macampplugin')
FOLDER = 'newpicks'
FIRST_BLOCK = 29
SHARED = {'mig-new4.avs': 27}  # deduplicated by the installer, see above
MAGIC = b'Nullsoft AVS Preset 0.'
EXPECTED = 112

header = open(os.path.join(RAW, '000_bin.dat'), 'rb').read()
strings = [s.decode('latin1') for s in re.findall(rb'[\x20-\x7e]{4,}', header)]
start = strings.index('elvis_first3d_pulsar.avs')
names = []
for s in strings[start:]:
    if not s.endswith('.avs'):
        break
    names.append(s)
if len(names) != EXPECTED:
    sys.exit(f'expected {EXPECTED} preset names, found {len(names)}')

shutil.rmtree(PACK, ignore_errors=True)
target = os.path.join(PACK, 'Contents', 'Resources', FOLDER)
os.makedirs(target)
block = FIRST_BLOCK
for name in names:
    index = SHARED.get(name)
    if index is None:
        index, block = block, block + 1
    data = open(os.path.join(RAW, f'{index:03d}_bin.dat'), 'rb').read()
    if not data.startswith(MAGIC):
        sys.exit(f'block {index:03d} for {name} is not an AVS preset')
    open(os.path.join(target, name), 'wb').write(data)

with open(os.path.join(PACK, 'Contents', 'Info.plist'), 'wb') as f:
    plistlib.dump({'CFBundleIdentifier': 'alexrel.MacAmp.avs-presets.winamp295',
                   'CFBundleName': 'Winamp 2.95 AVS Presets',
                   'MacAmpPluginKind': 'avs-presets',
                   'MacAmpPluginTitle': 'Winamp 2.95 AVS presets (newpicks)'}, f)
archive = PACK + '.zip'
if os.path.exists(archive):
    os.remove(archive)
subprocess.run(['ditto', '-c', '-k', '--keepParent', PACK, archive], check=True)
print(f'{len(names)} presets -> {PACK}\n{archive}')
