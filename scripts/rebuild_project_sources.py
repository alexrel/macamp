#!/usr/bin/env python3
import os
import re
import uuid

def generate_id(name):
    # Deterministic 24-character hex ID based on name
    return "AA" + uuid.uuid5(uuid.NAMESPACE_DNS, name).hex[:22].upper()

project_path = "MacAmp.xcodeproj/project.pbxproj"
with open(project_path, "r") as f:
    pbx = f.read()

# Collect all swift files in MacAmp
swift_files = []
for root, dirs, files in os.walk("MacAmp"):
    for file in sorted(files):
        if file.endswith(".swift"):
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, "MacAmp")
            swift_files.append((file, rel_path, full_path))

print(f"Found {len(swift_files)} Swift source files:")
for file, rel, full in swift_files:
    print(f"  {rel}")

# 1. Clear old PBXBuildFile entries for Swift files and resources
pbx = re.sub(r'\t\t[0-9A-F]{24} /\* .*?\.swift in Sources \*/ = \{isa = PBXBuildFile; .*?\};\n', '', pbx)
pbx = re.sub(r'\t\t[0-9A-F]{24} /\* base-2.91\.wsz in Resources \*/ = \{isa = PBXBuildFile; .*?\};\n', '', pbx)

# 2. Clear old PBXFileReference entries for Swift files and resources
pbx = re.sub(r'\t\t[0-9A-F]{24} /\* .*?\.swift \*/ = \{isa = PBXFileReference; .*?\};\n', '', pbx)
pbx = re.sub(r'\t\t[0-9A-F]{24} /\* base-2.91\.wsz \*/ = \{isa = PBXFileReference; .*?\};\n', '', pbx)

# 2b. Clear old base-2.91.wsz in Resources phase
pbx = re.sub(r'\t\t\t\t[0-9A-F]{24} /\* base-2.91\.wsz in Resources \*/,\n?', '', pbx)

# 3. Create new FileReferences and BuildFiles
file_refs = []
build_files = []
sources_entries = []

for file, rel, full in swift_files:
    f_id = generate_id("FILE_" + rel)
    b_id = generate_id("BUILD_" + rel)
    
    file_refs.append(f"\t\t{f_id} /* {file} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{file}\"; sourceTree = \"<group>\"; }};")
    build_files.append(f"\t\t{b_id} /* {file} in Sources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {file} */; }};")
    sources_entries.append(f"\t\t\t\t{b_id} /* {file} in Sources */,")

# Add base-2.91.wsz resource
wsz_file_id = generate_id("FILE_base-2.91.wsz")
wsz_build_id = generate_id("BUILD_base-2.91.wsz")
file_refs.append(f'\t\t{wsz_file_id} /* base-2.91.wsz */ = {{isa = PBXFileReference; lastKnownFileType = file; path = "base-2.91.wsz"; sourceTree = "<group>"; }};')
build_files.append(f'\t\t{wsz_build_id} /* base-2.91.wsz in Resources */ = {{isa = PBXBuildFile; fileRef = {wsz_file_id} /* base-2.91.wsz */; }};')

# Insert into PBXBuildFile section
pbx = re.sub(r'(/\* Begin PBXBuildFile section \*/\n)', r'\1' + "\n".join(build_files) + "\n", pbx)

# Insert into PBXFileReference section
pbx = re.sub(r'(/\* Begin PBXFileReference section \*/\n)', r'\1' + "\n".join(file_refs) + "\n", pbx)

# Insert into Resources section
pbx = re.sub(r'(/\* Resources \*/ = \{[\s\S]*?files = \()([\s\S]*?)(\);)', r'\1\n\t\t\t\t' + wsz_build_id + r' /* base-2.91.wsz in Resources */,\n\2\3', pbx)

# Insert into Sources section
pbx = re.sub(r'(/\* Sources \*/ = \{[\s\S]*?files = \()[\s\S]*?(\);)', r'\1\n' + "\n".join(sources_entries) + r'\n\t\t\t\2', pbx)

# 4. Build PBXGroup hierarchy for MacAmp
# Groups: Core, Skin, Audio, Playlist, Windowing, UI (with Components, MainWindow, EqualizerWindow, PlaylistWindow), State, Resources
def make_group(group_id, name, path, children_entries):
    children_str = "\n".join([f"\t\t\t\t{c}," for c in children_entries])
    return f"""\t\t{group_id} /* {name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children_str}
\t\t\t);
\t\t\tpath = "{path}";
\t\t\tsourceTree = "<group>";
\t\t}};"""

# Replace PBXGroup section
# Find the start and end of PBXGroup section
m = re.search(r'/\* Begin PBXGroup section \*/([\s\S]*?)/\* End PBXGroup section \*/', pbx)
if m:
    # Groups:
    g_core_id = generate_id("GROUP_Core")
    g_skin_id = generate_id("GROUP_Skin")
    g_audio_id = generate_id("GROUP_Audio")
    g_playlist_id = generate_id("GROUP_Playlist")
    g_windowing_id = generate_id("GROUP_Windowing")
    g_state_id = generate_id("GROUP_State")
    g_ui_id = generate_id("GROUP_UI")
    g_ui_comp_id = generate_id("GROUP_UI_Comp")
    g_ui_main_id = generate_id("GROUP_UI_Main")
    g_ui_eq_id = generate_id("GROUP_UI_Eq")
    g_ui_pl_id = generate_id("GROUP_UI_Pl")
    
    # Children arrays
    core_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("Core/")]
    skin_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("Skin/")]
    audio_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("Audio/")]
    playlist_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("Playlist/")]
    windowing_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("Windowing/")]
    state_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("State/")]
    
    ui_comp_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("UI/Components/")]
    ui_main_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("UI/MainWindow/")]
    ui_eq_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("UI/EqualizerWindow/")]
    ui_pl_children = [f"{generate_id('FILE_' + rel)} /* {file} */" for file, rel, _ in swift_files if rel.startswith("UI/PlaylistWindow/")]
    
    ui_children = [
        f"{g_ui_comp_id} /* Components */",
        f"{g_ui_main_id} /* MainWindow */",
        f"{g_ui_eq_id} /* EqualizerWindow */",
        f"{g_ui_pl_id} /* PlaylistWindow */",
    ]
    
    macamp_app_file_id = f"{generate_id('FILE_MacAmpApp.swift')} /* MacAmpApp.swift */"
    
    new_groups = f"""/* Begin PBXGroup section */
\t\tBDC069372B887D8B0009C001 = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tBDC069422B887D8B0009C001 /* MacAmp */,
\t\t\t\tBDC069412B887D8B0009C001 /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\tBDC069412B887D8B0009C001 /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tBDC069402B887D8B0009C001 /* MacAmp.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\tBDC069422B887D8B0009C001 /* MacAmp */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{g_core_id} /* Core */,
\t\t\t\t{g_skin_id} /* Skin */,
\t\t\t\t{g_audio_id} /* Audio */,
\t\t\t\t{g_playlist_id} /* Playlist */,
\t\t\t\t{g_windowing_id} /* Windowing */,
\t\t\t\t{g_ui_id} /* UI */,
\t\t\t\t{g_state_id} /* State */,
\t\t\t\t{macamp_app_file_id},
\t\t\t\t{wsz_file_id} /* base-2.91.wsz */,
\t\t\t\tBDC069472B887D910009C001 /* Assets.xcassets */,
\t\t\t\tBDC0694C2B887D910009C001 /* MacAmp.entitlements */,
\t\t\t\tBDC069492B887D910009C001 /* Preview Content */,
\t\t\t);
\t\t\tpath = MacAmp;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\tBDC069492B887D910009C001 /* Preview Content */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tBDC0694A2B887D910009C001 /* Preview Assets.xcassets */,
\t\t\t);
\t\t\tpath = "Preview Content";
\t\t\tsourceTree = "<group>";
\t\t}};
{make_group(g_core_id, "Core", "Core", core_children)}
{make_group(g_skin_id, "Skin", "Skin", skin_children)}
{make_group(g_audio_id, "Audio", "Audio", audio_children)}
{make_group(g_playlist_id, "Playlist", "Playlist", playlist_children)}
{make_group(g_windowing_id, "Windowing", "Windowing", windowing_children)}
{make_group(g_state_id, "State", "State", state_children)}
{make_group(g_ui_id, "UI", "UI", ui_children)}
{make_group(g_ui_comp_id, "Components", "Components", ui_comp_children)}
{make_group(g_ui_main_id, "MainWindow", "MainWindow", ui_main_children)}
{make_group(g_ui_eq_id, "EqualizerWindow", "EqualizerWindow", ui_eq_children)}
{make_group(g_ui_pl_id, "PlaylistWindow", "PlaylistWindow", ui_pl_children)}
/* End PBXGroup section */"""
    
    pbx = pbx[:m.start()] + new_groups + pbx[m.end():]

with open(project_path, "w") as f:
    f.write(pbx)

print("Successfully regenerated project.pbxproj!")
