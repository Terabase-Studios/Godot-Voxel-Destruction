# Godot Voxel Destruction

![Godot Voxel Destruction](https://github.com/Terabase-Studios/Godot-Voxel-Destruction/blob/main/Screenshots/Rigid%20Body%20Demo.png)

A flexible and efficient voxel-based destruction system for Godot 4.1+. This addon allows you to create dynamic, destructible objects from `.vox` files.

---

## Features

*   **Custom Importer:** Includes a custom importer for MagicaVoxel `.vox` files.
*   **High Performance:** Utilizes `MultiMeshInstance3D` for high-performance rendering of voxels.
*   **Debris Modes:** Offers multiple debris modes for varying levels of realism and performance.
*   **Dithering:** Supports adjustable dithering effects for enhanced visual realism during destruction.
*   **Easy Integration:** Designed for seamless integration into existing Godot projects.

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

## VoxelObject Settings

The `VoxelObject` node has several settings to customize its behavior:

| Setting         | Description                                                                                                                              |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `voxel_resource`  | The `VoxelResource` or `CompactVoxelResource` to display.                                                                                |
| `invulnerable`    | If `true`, the object cannot be damaged.                                                                                                 |
| `darkening`       | If `true`, damaged voxels will be darkened based on their health.                                                                        |
| `end_of_life`     | What the object should do when its health reaches 0 (`Nothing`, `Disable`, `Queue_free()`).                                                |
| `debris_type`     | The type of debris to generate (`None`, `Multimesh`, `Rigid Bodies`).                                                                      |
| `debris_weight`   | The strength of gravity on the debris.                                                                                                   |
| `debris_density`  | The chance of generating debris per destroyed voxel (0.0 to 1.0).                                                                        |
| `debris_lifetime` | The time in seconds before debris is deleted.                                                                                            |
| `maximum_debris`  | The maximum number of rigid body debris that can be active at once.                                                                      |
| `dark_dithering`  | The maximum amount of random darkening applied to voxels.                                                                                |
| `light_dithering` | The maximum amount of random lightening applied to voxels.                                                                               |
| `dithering_bias`  | The ratio of random darkening to lightening.                                                                                             |
| `dithering_seed`  | The seed used for the dithering effect.                                                                                                  |
| `physics`         | If `true`, the `VoxelObject` will act as a `RigidBody3D`. This is an experimental feature.                                                |
| `density`         | The density of the object in kilograms per cubic meter, used for mass calculations when `physics` is enabled.                            |
| `physics_material`| The `PhysicsMaterial` to use when `physics` is enabled.                                                                                  |
| `flood_fill`      | If `true`, disconnected voxels will be removed after destruction. This is an experimental feature.                                       |
| `queue_attacks`   | If `true`, damage attacks will be queued and processed one at a time. This can improve performance when many attacks happen at once. |
| `lod_addon`       | A `VoxelLODAddon` resource to enable Level of Detail for the object.                                                                    |

## API Reference

### VoxelDamager

*   `hit()`: Damages all `VoxelObject`s within the damager's range.

### VoxelObject

*   `update_physics()`: Recalculates the center of mass and wakes the object if `physics` is enabled. This is called automatically when voxels are damaged.

## Contributing

Contributions are welcome! If you find a bug or have an idea for a new feature, please open an issue on the GitHub repository.

## License

This addon is licensed under the MIT License. See the `LICENSE` file for more details.