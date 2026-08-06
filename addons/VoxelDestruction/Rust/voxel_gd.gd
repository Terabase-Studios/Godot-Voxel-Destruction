extends RefCounted
class_name VoxelGD


static func get_voxels_in_aabb(aabb: AABB, vox_size: Vector3, positions_dict: Dictionary[Vector3i, int], object_global_transform: Transform3D) -> Array:
	var voxels := []
	var voxel_positions := PackedVector3Array()
	var global_voxel_positions := PackedVector3Array()
	var voxel_count: int = 0

	# Scale the transform to match the size of each voxel
	var scaled_basis := object_global_transform.basis.scaled(vox_size)
	var voxel_transform := Transform3D(scaled_basis, object_global_transform.origin)

	for voxel_pos: Vector3 in positions_dict.keys():
		# Center voxel in its grid cell
		var local_voxel_centered = voxel_pos + Vector3(0.5, 0.5, 0.5)

		# Convert to global space using full transform
		var voxel_global_pos = voxel_transform * local_voxel_centered

		if aabb.has_point(voxel_global_pos):
			var voxid = positions_dict.get(Vector3i(voxel_pos), -1)
			if voxid != -1:
				voxel_count += 1
				voxel_positions.append(voxel_pos)
				global_voxel_positions.append(voxel_global_pos)

	voxels.append(voxel_count)
	voxels.append(voxel_positions)
	voxels.append(global_voxel_positions)
	return voxels


# BFS from origin. Returns a Dictionary mapping voxel -> group_index,
# and populates groups (Array of Arrays of Vector3i).
# The group containing origin is group 0 (the "anchored" group that stays).
static func flood_fill_groups(positions_dict: Dictionary) -> Array:
	var offsets = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)
	]
	var visited := {}
	var groups := []  # Array of PackedVector3Array

	for start_vox in positions_dict.keys():
		if visited.has(start_vox):
			continue
		# BFS from this unvisited voxel
		var group := []
		var queue := [start_vox]
		var qi := 0
		visited[start_vox] = true
		while qi < queue.size():
			var cur: Vector3i = queue[qi]
			qi += 1
			group.append(cur)
			for offset in offsets:
				var nb: Vector3i = cur + offset
				if not visited.has(nb) and positions_dict.has(nb):
					visited[nb] = true
					queue.append(nb)
		groups.append(group)

	return groups
