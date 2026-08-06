extends RefCounted
class_name VoxelGD


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
	var range_squared := range * range
	
	var damage_results := []
	damage_results.resize(voxel_count)
	for voxel in range(voxel_count):
		# Get positions and vox_ids to modify later and calculate damage
		var vox_position: Vector3 = global_voxel_positions[voxel]
		var vox_pos3i: Vector3i = voxel_positions[voxel]
		var vox_id: int = positions_dict.get(vox_pos3i, -1)

		# Skip if voxel ID is invalid
		if vox_id == -1:
			continue

		var decay: float = damager_global_pos.distance_squared_to(vox_position) / range_squared
		var attack_sample: float = damage_curve.sample(decay)

		# Skip processing if damage is negligible
		if attack_sample <= 0.01:
			continue

		var power_sample: float = power_curve.sample(decay)
		var damage: float = damage_base * attack_sample
		var power: float = power_base * power_sample

		# Compute new voxel health
		var new_health: float = clamp(voxel_health_array[vox_id] - damage, 0, 100)

		var chunk = Vector3.ZERO
		var chunk_pos = 0
		if new_health == 0:
			chunk = chunk_indices[vox_id]
			var chunk_data = chunks.get(chunk, [])
			chunk_pos = chunk_data.find(vox_pos3i) if chunk_data else -1

		# Store the result in a thread-safe dictionary
		damage_results[voxel] = {
			"vox_id": vox_id,
			"health": new_health,
			"pos": vox_pos3i,
			"chunk": chunk,
			"chunk_pos": chunk_pos,
			"power": power,
		}
	return damage_results


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
