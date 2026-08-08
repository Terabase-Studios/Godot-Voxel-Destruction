
use std::collections::HashSet;

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
        const HALF_VOXEL: Vector3 = Vector3::new(0.5, 0.5, 0.5);
        
        let mut voxels: Array<Variant> = Array::new();
        
        // Scale the transform to match the size of each voxel
        let scaled_basis = object_global_transform.basis.scaled(vox_size);
        let voxel_transform = Transform3D::new(scaled_basis, object_global_transform.origin);

        // Convert AABB to a bounding box
        let min = aabb.position;
        let max = aabb.position + aabb.size;
        let corners = [
            Vector3::new(min.x, min.y, min.z),
            Vector3::new(max.x, min.y, min.z),
            Vector3::new(min.x, max.y, min.z),
            Vector3::new(max.x, max.y, min.z),

            Vector3::new(min.x, min.y, max.z),
            Vector3::new(max.x, min.y, max.z),
            Vector3::new(min.x, max.y, max.z),
            Vector3::new(max.x, max.y, max.z),
        ];
        // Transform bounding box to local space
        let inv_voxel_transform = voxel_transform.affine_inverse();
        let mut local_min = Vector3::new(f32::INFINITY, f32::INFINITY, f32::INFINITY);
        let mut local_max = Vector3::new(f32::NEG_INFINITY, f32::NEG_INFINITY, f32::NEG_INFINITY);
        for corner in corners {
            let local = inv_voxel_transform * corner;

            local_min.x = local_min.x.min(local.x);
            local_min.y = local_min.y.min(local.y);
            local_min.z = local_min.z.min(local.z);

            local_max.x = local_max.x.max(local.x);
            local_max.y = local_max.y.max(local.y);
            local_max.z = local_max.z.max(local.z);
        }
        let min_voxel = (local_min - HALF_VOXEL).floor().cast_int();
        let max_voxel = (local_max - HALF_VOXEL).ceil().cast_int();

        // Convert to Rust typing
        let voxel_set: HashSet<Vector3i> = positions_dict
            .iter_shared()
            .map(|(k, _v)| k)
            .collect();

        let box_volume = ((max_voxel.x - min_voxel.x + 1)
            * (max_voxel.y - min_voxel.y + 1)
            * (max_voxel.z - min_voxel.z + 1)).max(0) as usize;
        
        // Reserve space to prevent allocation
        let reserve = box_volume.min(voxel_set.len());
        let mut voxel_positions: Vec<Vector3i> = Vec::with_capacity(reserve);
        let mut global_voxel_positions: Vec<Vector3> = Vec::with_capacity(reserve);


        for x in min_voxel.x..=max_voxel.x {
            for y in min_voxel.y..=max_voxel.y {
                for z in min_voxel.z..=max_voxel.z {
                    let voxel_pos_i = Vector3i::new(x, y, z);

                    if !voxel_set.contains(&voxel_pos_i) {
                        continue;
                    }

                    let voxel_pos = voxel_pos_i.cast_float();
                    let local_voxel_centered = voxel_pos + HALF_VOXEL;
                    let voxel_global_pos = voxel_transform * local_voxel_centered;

                    voxel_positions.push(voxel_pos_i);
                    global_voxel_positions.push(voxel_global_pos);
                }
            }
        }

        let voxel_count = voxel_positions.len() as u32;

        // Back to godot types
        let godot_voxel_positions: Array<Vector3i> = voxel_positions.into_iter().collect();
        let godot_global_positions: PackedVector3Array = global_voxel_positions.into_iter().collect();

        voxels.push(&Variant::from(voxel_count));
        voxels.push(&Variant::from(godot_voxel_positions));
        voxels.push(&Variant::from(godot_global_positions));
        return voxels;
    }

    // BFS from origin. Returns a Dictionary mapping voxel -> group_index,
    // and populates groups (Array of Arrays of Vector3i).
    // The group containing origin is group 0 (the "anchored" group that stays).
    #[func]
    fn flood_fill_groups(positions_dict: Dictionary<Vector3i, i32>) -> Array<Variant> {
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