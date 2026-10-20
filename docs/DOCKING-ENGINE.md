# DOCKING-ENGINE.md

This document describes the architecture and behavior of the **MacAmp Magnetic Docking Engine**, designed to replicate the pixel-perfect window management of Winamp 2.91.

---

## 🏗️ Core Architecture: The Rigid Guardian

The system uses a **Magnetic Graph** to manage relationships and AppKit's native **`addChildWindow`** for the physical movement propagation.

### 1. Hierarchical Leadership
- **Main (The Vertex)**: The player is the absolute root of the hierarchy. If the Main window moves, the entire docked group moves with it with zero lag.
- **Slaves (EQ & Playlist)**: These windows follow the leader. However, if a user drags a Slave window, it immediately detaches from the group and moves independently ("it pulls nothing behind it").

### 2. The Directed Acyclic Graph (DAG)
To prevent infinite recursion and application crashes (common when two windows try to be parents of each other), the `WindowLayoutManager` maintains a directed graph:
- **Edges**: Stored as `[ChildID: ParentID]`.
- **Validation**: Before any snap is established, the engine performs a cycle check (`wouldCreateCycle`). If a loop is detected, the snap is rejected.

---

## ⚓ Magnetic Snapping Logic

### 1. Unified 10px Magnetism
- Windows search for neighbors within a **10-pixel threshold**.
- Snapping works in all directions: **Top, Bottom, Left, and Right**.
- **Bi-directional**: The Player can snap to Slaves, and Slaves can snap to the Player. Regardless of who initiated the snap, the **Main Player** is always assigned as the Parent.

### 2. Corner Alignment
When a window snaps to a horizontal or vertical edge, the engine also checks for **secondary axis alignment**. If the corners are close enough, they are automatically flushed, ensuring a clean "brick-like" layout.

---

## 📏 Root-Relative Scaling Engine

A major feature of the engine is handling transitions between **1x and 2x scales** without gaps or overlaps.

### 1. The Logical Snapshot
Before a scale change occurs, the engine takes a "logical snapshot" of the group:
- It calculates the distance of every window relative to the **Main window's Top-Left corner**.
- These distances are normalized into **Logical Pixels (1x)**.

### 2. Geometric Propagation
After the windows are resized:
- The Main window remains at its current Top-Left position.
- Every other window is repositioned using its logical offset multiplied by the new scale.
- **Integer Precision**: All final coordinates are rounded to the nearest pixel to eliminate sub-pixel "jitter" or "dancing" windows.

---

## 🛡️ Stability & Performance
- **Sub-Pixel Smoothness**: By leveraging native AppKit parent-child windows, we avoid the overhead and lag of manual frame calculation during drags.
- **Atomic Detachment**: Links are broken in `windowWillMove`, ensuring a clean separation before the OS begins the drag operation.
- **Z-Order Management**: Child windows (EQ, PL) are strictly ordered `.above` the Main window, preventing them from ever being hidden behind the player.
