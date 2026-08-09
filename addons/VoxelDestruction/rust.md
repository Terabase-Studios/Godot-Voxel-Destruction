## How to use Rust Gdextension
### Install rust
```
# Linux (distro-independent)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Windows
winget install -e --id Rustlang.Rustup

# macOS
brew install rustup
```

### Compile Gdextension
```
cd addons/VoxelDestruction/Rust/voxel_native # Go to the Rust project's directory
cargo build # Compile the project
```

### Final Setup
1. Go to `addons/VoxelDestruction/Rust` and rename `voxel_native.txt` to `voxel_native.gdextention`  
2. In Godot, go to your project settings and toggle `Advanced Settings` to on.  
Then set `voxel_destruction/performance/rust_gdextention` to true and reload the editor

Note: You will probably see the errors:
```
 WARNING: platform/windows/windows_utils.cpp:184 - The original path size of 'voxel_native.pdb' in bytes was too small to fit the new name, so it was shortened to '~voxel_n_999.pdb'.
 ERROR: Signal 'cell_selected' is already connected to given callable 'GDScript::_on_editor_inspector_changed' in that object.
 ERROR: Signal 'cell_selected' is already connected to given callable 'GDScript::_on_project_inspector_changed' in that object.
```
This is normal. =)

---

## Exporting
This is more complicated. Please see the official [Godot-Rust Guide](https://godot-rust.github.io/gdnative-book/export/index.html)