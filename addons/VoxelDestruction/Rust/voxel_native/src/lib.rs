
use godot::{prelude::*};

struct MyExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}


#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct VoxelNative {
    base: Base<RefCounted>
}

#[godot_api]
impl VoxelNative {
    #[func]
    fn get_voxels_in_aabb(aabb: Aabb, vox_size: Vector3, positions_dict: Dictionary<Vector3i, i64>, object_global_transform: Transform3D) -> Array<Variant> {
        let mut voxels: Array<Variant> = Array::new();
        let mut voxel_positions: Array<Vector3i> = Array::new();
        let mut global_voxel_positions: Array<Vector3> = Array::new();
        let mut voxel_count: u32 = 0;
        
        // Scale the transform to match the size of each voxel
        let scaled_basis = object_global_transform.basis.scaled(vox_size);
        let voxel_transform = Transform3D::new(scaled_basis, object_global_transform.origin);

        let keys = positions_dict.keys_array();
        for i in 0..keys.len() {
            let voxel_pos_i = keys.get(i).unwrap();
            let voxel_pos = Vector3::new(
                voxel_pos_i.x as f32, 
                voxel_pos_i.y as f32, 
                voxel_pos_i.z as f32
            );
            // Center voxel in its grid cell
            let local_voxel_centered = voxel_pos + Vector3::new(0.5, 0.5, 0.5);

            // Convert to global space using full transform
            let voxel_global_pos = voxel_transform * local_voxel_centered;

            if aabb.contains_point(voxel_global_pos) {
                let voxid = positions_dict.get(voxel_pos.cast_int());
                if voxid.is_none() {
                    continue;
                }
                voxel_count += 1;
                voxel_positions.push(voxel_pos_i);
                global_voxel_positions.push(voxel_global_pos)
            }
        }
        voxels.push(&Variant::from(voxel_count));
        voxels.push(&Variant::from(voxel_positions));
        voxels.push(&Variant::from(global_voxel_positions));
        return voxels
    }

    // BFS from origin. Returns a Dictionary mapping voxel -> group_index,
    // and populates groups (Array of Arrays of Vector3i).
    // The group containing origin is group 0 (the "anchored" group that stays).
    #[func]
    fn flood_fill_groups(positions_dict: Dictionary<Vector3i, bool>) -> Array<Variant> {
        const OFFSETS: [Vector3i; 6] = [
            Vector3i::new(1, 0, 0),
            Vector3i::new(-1, 0, 0),
            Vector3i::new(0, 1, 0),
            Vector3i::new(0, -1, 0),
            Vector3i::new(0, 0, 1),
            Vector3i::new(0, 0, -1),
        ];
        
        let mut visited: Dictionary<Vector3i, bool> = Dictionary::new();
        let mut groups: Array<Variant> = Array::new();
        
        let keys = positions_dict.keys_array();
        for i in 0..keys.len() {
            let start_vox = keys.get(i).unwrap();
            if visited.contains_key(start_vox) {
                continue;
            }
            // BFS from this unvisited voxel
            let mut group: Array<Vector3i> = Array::new();
            let mut queue: Array<Vector3i> = Array::new();
            queue.push(start_vox);
            let mut qi = 0;
            visited.set(start_vox, true);
            while qi < queue.len() {
                let cur = queue.get(qi).unwrap();
                qi += 1;
                group.push(cur);
                for offset in OFFSETS {
                    let nb = cur + offset;
                    if !visited.contains_key(nb) && positions_dict.contains_key(nb) {
                        visited.set(nb, true);
                        queue.push(nb);
                    }
                }
            }
            groups.push(&Variant::from(group));
        }
        return groups
    }
}