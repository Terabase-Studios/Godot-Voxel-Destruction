# Godot Voxel Destruction

![Godot Voxel Destruction](https://github.com/Terabase-Studios/Godot-Voxel-Destruction/blob/main/Screenshots/Rigid%20Body%20Demo.png)

A flexible and efficient voxel-based destruction system for Godot 4.1+. This addon allows you to create dynamic, destructible objects from `.vox` files.  
Please checkl out the [roadmap](https://github.com/users/Terabase-Studios/projects/2)!

---

## Features

*   **Custom Importer:** Includes a custom importer for MagicaVoxel `.vox` files.
*   **High Performance:** Utilizes `MultiMeshInstance3D` for high-performance rendering of voxels.
*   **Debris Modes:** Offers multiple debris modes for varying levels of realism and performance.
*   **Dithering:** Supports adjustable dithering effects for enhanced visual realism during destruction.
*   **Easy Integration:** Designed for seamless integration into existing Godot projects.
*   **VoxelObject Health and Damage tracking** Mark voxels and track health for enemies or indivisual voxels.
*   **Custom Monitors** View VoxelDestruction specific statistics real time in Debugger/Monitors.
*   **Custom Project Settings** Change VoxelDestruction specific settings built into the ProjectSettings.


## Contribution
I want to make this the best addon it can be! Feel free to open an issue or pull request. If you need any assistance whats so ever, please reach me at terabasestudios@gmail.com =)

## Installation

1.  **Godot Asset Library:**
	*   Open the "AssetLib" tab in the Godot editor.
	*   Search for "Voxel Destruction" and click on the addon.
	*   Click "Download" and then "Install".

2.  **Enable the Plugin:**
	*   Go to `Project` > `Project Settings` > `Plugins`.
	*   Find "Voxel Destruction" in the list and check the "Enable" box.

## Getting Started

1.  **Import a `.vox` file:**
	*   Drag and drop a `.vox` file into your project's file system.
    *   The custom importer will automatically create a `VoxelResource` file.

2.  **Create a `VoxelObject`:**
    *   Add a `VoxelObject` node to your scene.
    *   In the Inspector, assign the `VoxelResource` you just created to the `Voxel Resource` property of the `VoxelObject`.
    *   Click the `(Re)populate Mesh` button at the top of the Inspector.

3.  **Create a `VoxelDamager`:**
    *   Add a `VoxelDamager` node to your scene. This is an `Area3D` that defines the area of effect for damage.
    *   Add a `CollisionShape3D` to the `VoxelDamager` with a `BoxShape3D`. The size of the box determines the range of the damager.

4.  **Damage the `VoxelObject`:**
    *   Call the `hit()` function on the `VoxelDamager` to damage any `VoxelObject`s within its range.

    ```gdscript
    # Example of how to use the VoxelDamager
    func _physics_process(delta):
        if Input.is_action_just_pressed("fire"):
            $VoxelDamager.hit()
    ```

## API Reference

### VoxelDamager

*   `hit()`: Damages all `VoxelObject`s within the damager's range.

## Contributing

Contributions are welcome! If you find a bug or have an idea for a new feature, please open an issue on the GitHub repository.

## License

This addon is licensed under the MIT License. See the `LICENSE` file for more details.
