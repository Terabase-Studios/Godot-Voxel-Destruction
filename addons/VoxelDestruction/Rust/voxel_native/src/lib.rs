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
    fn get_voxels_in_aabb() -> () {
        godot_print!("testing");
    }

    #[func]
    fn flood_fill_groups(positions_dict: Dictionary<Vector3i, bool>) -> Array<Variant> {
        let offsets: [Vector3i; 6] = [
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
                for offset in offsets {
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