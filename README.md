# Asset Forge

Godot 4 editor plugin for batch importing GLTFs and splitting meshes. Built because doing this stuff manually takes forever.

## What it does

Two tabs in the editor dock:

**Batch Import** — Point it at a folder of `.gltf`/`.glb` files and it will:
- Load them all and save each as a `.tscn`
- Extract materials into standalone `.tres` files (so you can swap them easily)
- Generate a GridMap `MeshLibrary` with auto convex collision
- Organize everything into subfolders you define

**Mesh Splitter** — Takes a single GLB with multiple meshes (like character body parts) and splits each `MeshInstance3D` into its own `.tscn`. No more "make local → set as root → delete everything else → save as" for every single part.

## Install

1. Download or clone this repo
2. Copy the `addons/asset_forge` folder into your project's `addons/` directory
3. Project → Project Settings → Plugins → Enable "Asset Forge"
4. The dock shows up on the right side of the editor

## Usage

Pretty straightforward — set your source folder/file, set your output folder, toggle what you need, hit the button. Logs show up at the bottom of each tab.

For batch import, you can configure the subfolder names (defaults to `scenes/`, `materials/`, `mesh_library/`) and the spacing between models on the X axis.

## Needs

- Godot 4.x

## License

MIT
