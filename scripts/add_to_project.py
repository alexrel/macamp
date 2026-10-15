#!/usr/bin/env python3
import sys
import os
import re
import uuid

def generate_id():
    return "AA" + os.urandom(11).hex().upper()

def add_file_to_project(file_path, project_path):
    # Always work with relative path from project root
    project_root = str(os.path.dirname(os.path.abspath(project_path)))
    if project_root.endswith('.xcodeproj'):
        project_root = os.path.dirname(project_root)
        
    rel_file_path = os.path.relpath(os.path.abspath(file_path), project_root)
    file_name = os.path.basename(rel_file_path)
    
    # Determine group based on the immediate parent directory
    parent_dir = os.path.basename(os.path.dirname(rel_file_path))
    # If it's deeper (e.g. MacAmp/Views/Components), we want the immediate parent
    group_name = parent_dir if parent_dir else "MacAmp"
    
    print(f"Adding {file_name} to group '{group_name}' (Path: {rel_file_path})")
    
    with open(project_path, 'r') as f:
        content = f.read()
        
    # Check if we have the reference already
    file_ref_id = None
    ref_match = re.search(rf'([0-9A-F]{{24}}) /\* {file_name} \*/ = {{isa = PBXFileReference;', content)
    if ref_match:
        file_ref_id = ref_match.group(1)
        print(f"Found existing FileRef: {file_ref_id}")
    else:
        file_ref_id = generate_id()
        print(f"Generated new FileRef: {file_ref_id}")
        file_ref_entry = f"\t\t{file_ref_id} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = \"<group>\"; }};\n"
        content = re.sub(r'(/\* End PBXFileReference section \*/)', file_ref_entry + r'\1', content)
        
        # Add to Group
        group_pattern = rf'(/\* {group_name} \*/ = \{{[\s\S]*?children = \()([\s\S]*?)(\);)'
        if re.search(group_pattern, content):
            content = re.sub(group_pattern, rf'\1\2\t\t\t\t{file_ref_id} /* {file_name} */,\n\3', content)
        else:
            # Fallback to main group if specific group not found
            print(f"Warning: Group {group_name} not found, adding to root.")
            root_group_pattern = r'(isa = PBXGroup;[\s\S]*?children = \()([\s\S]*?)(\);)'
            content = re.sub(root_group_pattern, rf'\1\2\t\t\t\t{file_ref_id} /* {file_name} */,\n\3', content, 1)

    # Build File entry
    build_file_id = None
    build_match = re.search(rf'([0-9A-F]{{24}}) /\* {file_name} in Sources \*/ = {{isa = PBXBuildFile;', content)
    if build_match:
        build_file_id = build_match.group(1)
        print(f"Found existing BuildFile: {build_file_id}")
    else:
        build_file_id = generate_id()
        print(f"Generated new BuildFile: {build_file_id}")
        build_file_entry = f"\t\t{build_file_id} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {file_name} */; }};\n"
        content = re.sub(r'(/\* End PBXBuildFile section \*/)', build_file_entry + r'\1', content)
        
        # Add to Sources Build Phase
        sources_pattern = r'(/\* Sources \*/ = \{[\s\S]*?files = \()([\s\S]*?)(\);)'
        content = re.sub(sources_pattern, rf'\1\2\t\t\t\t{build_file_id} /* {file_name} in Sources */,\n\3', content)
    
    with open(project_path, 'w') as f:
        f.write(content)
    
    print(f"Successfully processed {file_name} in {project_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: add_to_project.py <file_path> <project_pbxproj_path>")
        sys.exit(1)
    add_file_to_project(sys.argv[1], sys.argv[2])
