#!/usr/bin/env python3
"""Builds a pack of skins MacAmp installs in one go: build/plugins/<Name>.macampplugin and, for the site and the
release, build/<Name with dashes>.zip. Dropped on MacAmp, the pack's skins go into the Skins folder (same names replaced).

HD skins (.msz) must be HD as MacAmp defines it: 4x only, MAIN at 1100x464 (275x116 times 4); others are refused here
the way MacAmp would refuse them. Classic .wsz skins go in as they are.

Usage: python3 scripts/build_skins_pack.py "MacAmp HD Skins" "MacAmp HD skins (Winamp 5 Classified...)" skin.msz ...
"""
import os, plistlib, shutil, struct, subprocess, sys, zipfile

HD_EXTENSION, CLASSIC_EXTENSION = '.msz', '.wsz'
HD_SCALE, MAIN_WIDTH, MAIN_HEIGHT = 4, 275, 116  # AppConstants.Skins.hdScale, AppConstants.Window.width / height

def main_size(path):
    """MAIN.png's width and height from its PNG header (IHDR)"""
    with zipfile.ZipFile(path) as skin:
        name = next((n for n in skin.namelist() if os.path.basename(n).lower() == 'main.png'), None)
        if name is None:
            return None
        header = skin.read(name)[:24]
    return struct.unpack('>II', header[16:24])

if len(sys.argv) < 4:
    sys.exit(__doc__)
name, title, skins = sys.argv[1], sys.argv[2], sys.argv[3:]
for path in skins:
    ext = os.path.splitext(path)[1].lower()
    if ext not in (HD_EXTENSION, CLASSIC_EXTENSION):
        sys.exit(f'{path}: not a .msz or .wsz skin')
    if ext == HD_EXTENSION and main_size(path) != (MAIN_WIDTH * HD_SCALE, MAIN_HEIGHT * HD_SCALE):
        sys.exit(f'{path}: not a {HD_SCALE}x HD skin (MAIN.png {main_size(path)})')

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pack = os.path.join(root, 'build', 'plugins', f'{name}.macampplugin')
archive = os.path.join(root, 'build', name.replace(' ', '-') + '.zip')
shutil.rmtree(pack, ignore_errors=True)
resources = os.path.join(pack, 'Contents', 'Resources')
os.makedirs(resources)
for path in skins:
    shutil.copy(path, resources)
with open(os.path.join(pack, 'Contents', 'Info.plist'), 'wb') as f:
    plistlib.dump({'CFBundleIdentifier': 'alexrel.MacAmp.skins.' + name.lower().replace(' ', '-'),
                   'CFBundleName': name, 'MacAmpPluginKind': 'skins', 'MacAmpPluginTitle': title}, f)
if os.path.exists(archive):
    os.remove(archive)
subprocess.run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--noacl', '--keepParent', pack, archive], check=True)
print(f'{len(skins)} skins -> {pack}\n{archive}')
