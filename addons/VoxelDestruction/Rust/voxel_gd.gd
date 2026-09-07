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

	var result_voxel_ids := PackedInt32Array()
	var result_health := PackedFloat32Array()
	var result_positions := PackedVector3Array()
	var result_chunks := PackedVector3Array()
	var result_chunk_positions := PackedInt32Array()
	var result_power := PackedFloat32Array()

	result_voxel_ids.resize(voxel_count)
	result_health.resize(voxel_count)
	result_positions.resize(voxel_count)
	result_chunks.resize(voxel_count)
	result_chunk_positions.resize(voxel_count)
	result_power.resize(voxel_count)

	var result_count := 0

	for voxel in range(voxel_count):
		var vox_position: Vector3 = global_voxel_positions[voxel]
		var vox_pos3i: Vector3i = voxel_positions[voxel]

		var vox_id: int = positions_dict.get(vox_pos3i, -1)

		if vox_id == -1:
			continue

		var decay: float = (
			damager_global_pos.distance_squared_to(vox_position)
			/ range_squared
		)

		var attack_sample: float = damage_curve.sample(decay)

		if attack_sample <= 0.01:
			continue

		var power_sample: float = power_curve.sample(decay)

		var damage: float = damage_base * attack_sample
		var power: float = power_base * power_sample

		var new_health: float = clamp(
			voxel_health_array[vox_id] - damage,
			0.0,
			100.0
		)

		var chunk := Vector3.ZERO
		var chunk_pos := -1

		if new_health == 0.0:
			chunk = chunk_indices[vox_id]

			var chunk_data: PackedVector3Array = chunks.get(
				chunk,
				PackedVector3Array()
			)

			if not chunk_data.is_empty():
				chunk_pos = chunk_data.find(vox_pos3i)

		result_voxel_ids[result_count] = vox_id
		result_health[result_count] = new_health
		result_positions[result_count] = Vector3(
			vox_pos3i.x,
			vox_pos3i.y,
			vox_pos3i.z
		)
		result_chunks[result_count] = chunk
		result_chunk_positions[result_count] = chunk_pos
		result_power[result_count] = power

		result_count += 1

	result_voxel_ids.resize(result_count)
	result_health.resize(result_count)
	result_positions.resize(result_count)
	result_chunks.resize(result_count)
	result_chunk_positions.resize(result_count)
	result_power.resize(result_count)

	return [
		result_voxel_ids,
		result_health,
		result_positions,
		result_chunks,
		result_chunk_positions,
		result_power
	]


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

