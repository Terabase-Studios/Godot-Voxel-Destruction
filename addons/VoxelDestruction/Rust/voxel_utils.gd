extends RefCounted
class_name VoxelUtilities

# This is called from VoxelServer
static func _init_called_from_server() -> void:
	var gd_available = ClassDB.class_exists("VoxelNative")
	VoxelServer._use_gd_ext = ProjectSettings.get_setting("voxel_destruction/performance/rust_gdextention", false)
	if Engine.is_editor_hint():
		if not gd_available and VoxelServer._use_gd_ext:
			push_warning("[VD Addon] Rust GdExtention is enabled but not compiled!")
		elif gd_available and not VoxelServer._use_gd_ext:
			push_warning("[VD Addon] Rust GdExtention is compiled but not enabled!")
		elif not gd_available and not VoxelServer._use_gd_ext:
			return
		elif gd_available and VoxelServer._use_gd_ext:
			var version = Engine.get_version_info()
			if not (version.major == 4 and version.minor >= 7):
				push_error("[VD Addon] Rust GdExtension requires at least godot 4.7!")
				VoxelServer._use_gd_ext = false
				return
			print("[VD Addon] VoxelNative successfully loaded!")


static func calculate_voxels_damage(
	voxel_count: int, 
	voxel_positions: PackedVector3Array, 
	positions_dict: Dictionary, 
	global_voxel_positions: PackedVector3Array, 
	voxel_health_array: PackedByteArray,
	chunk_indices: PackedVector3Array,
	chunks: Dictionary[Vector3, PackedVector3Array],
	range: float, 
	damage_base: float, 
	damage_curve: Curve, 
	power_base: int, 
	power_curve: Curve, 
	damager_global_pos: Vector3
) -> Array:                                                                   
	return VoxelGD.calculate_voxels_damage(voxel_count, voxel_positions, positions_dict, global_voxel_positions, voxel_health_array, chunk_indices, chunks, range, damage_base, damage_curve, power_base, power_curve, damager_global_pos)


static func get_voxels_in_aabb(aabb: AABB, vox_size: Vector3, positions_dict: Dictionary[Vector3i, int], object_global_transform: Transform3D) -> Array:
	var gd_available = ClassDB.class_exists("VoxelNative")
	if gd_available and VoxelServer._use_gd_ext:
		return ClassDB.instantiate("VoxelNative").get_voxels_in_aabb(aabb, vox_size, positions_dict, object_global_transform)
	else:
		return VoxelGD.get_voxels_in_aabb(aabb, vox_size, positions_dict, object_global_transform)
	return []


# BFS from origin. Returns a Dictionary mapping voxel -> group_index,
# and populates groups (Array of Arrays of Vector3i).
# The group containing origin is group 0 (the "anchored" group that stays).
static func flood_fill_groups(positions_dict: Dictionary[Vector3i, int]) -> Array:
	var gd_available = ClassDB.class_exists("VoxelNative")
	if gd_available and VoxelServer._use_gd_ext:
		return ClassDB.instantiate("VoxelNative").flood_fill_groups(positions_dict)
	else:
		return VoxelGD.flood_fill_groups(positions_dict)
	return []
