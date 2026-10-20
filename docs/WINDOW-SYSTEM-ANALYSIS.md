# WINDOW-SYSTEM-ANALYSIS.md

This document provides a comprehensive technical breakdown of the MacAmp window management system, its implementation details, performance characteristics, and resolved challenges.

---

## 🛠️ Core Technologies
- **AppKit (`NSWindow`)**: Used as the primary engine for window manipulation. Native AppKit calls provide the granularity required for pixel-perfect Winamp replication.
- **SwiftUI**: Acts as the UI layer for window content and reactive state management (Volume, Scale, Mode).
- **Magnetic Graph (Directed Acyclic Graph)**: A custom-built logical layer that manages parent-child relationships between window IDs.
- **Coordinate Normalization**: A mathematical layer that converts absolute screen coordinates into logical "Winamp pixels" (1x) for scaling consistency.

---

## 🚀 Performance Characteristics
### 1. Zero-Lag Movement
The "Rigid Guardian" architecture leverages the macOS Window Server's native `addChildWindow` API. This means that when the Main window is dragged, the OS moves all child windows simultaneously. There is **zero CPU overhead** during movement, and no "jelly lag" or synchronization jitter.

### 2. Atomic Detachment
By breaking connections in `windowWillMove` (before the drag begins), the system remains responsive. The separation is instant, and the OS does not have to reconcile competing movement signals.

### 3. Lightweight State
The entire docking hierarchy is maintained in a simple Swift dictionary. This ensures O(1) lookups for parent-child relations and O(N) for recursion/cycle checks, where N is the number of windows (currently max 3).

---

## ✅ Resolved & Implemented Features

### 1. Magnetic Snapping
- **Solved**: Unreliable "touching" detection.
- **Implementation**: 10px threshold sniffing in all 4 directions with automatic corner alignment.

### 2. Bi-Directional Docking
- **Solved**: Only Slaves could snap to Main.
- **Implementation**: Main can now snap to Slaves. Regardless of which window initiates the snap, the system correctly identifies and enforces Main as the absolute Parent (Leader).

### 3. Z-Order Occlusion
- **Solved**: Slaves hiding or flickering behind the Main player window.
- **Implementation**: Explicit `ordered: .above` enforcement during `addChildWindow`. Slaves are physically locked on top of the parent layer.

### 4. Seamless Scaling (1x/2x Transition)
- **Solved**: Windows "dancing," overlapping, or leaving gaps when switching scales.
- **Implementation**: **Root-Relative Scaling Engine**. The system takes a logical snapshot of offsets relative to Main's top-left corner and reapplies them with integer precision after resizing.

### 5. Cycle Prevention (Anti-Crash)
- **Solved**: Application crashes caused by circular docking (A docks to B, B docks to A).
- **Implementation**: DFS (Depth-First Search) cycle detection before establishing any new connection.

---

## ⚖️ Pros & Cons

### Pros
- **Authenticity**: Replicates the exact "feel" and behavior of Winamp 2.91 on modern macOS.
- **Rigidity**: Windows stay perfectly flush, even during rapid movement or resizing.
- **Stability**: Graph-based validation prevents system-level recursive hangs.
- **Persistence**: Remembers exactly how your "triangle" was arranged between app launches.

### Cons
- **Platform Limitation**: Deeply tied to AppKit and `NSWindow` (Apple-only).
- **Coordinate Space Complexity**: Managing the discrepancy between AppKit's bottom-left origin and the project's top-left logic requires careful pointer math.
- **Group Management Overhead**: Managing scale for 3 independent windows simultaneously requires a central coordinator (`WindowLayoutManager`).

---

## 📅 Summary of Current State
The window management system is currently **bulletproof** and behaves identically to the original Winamp interface. It is stabilized for 1x/2x scale transitions, supports all 3 primary windows (Main, EQ, PL), and provides a lag-free, premium experience.
