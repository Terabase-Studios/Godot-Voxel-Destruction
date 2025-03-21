@tool
@icon("voxel_object.svg")
extends MultiMeshInstance3D
class_name VoxelObject
## Displays and controls a VoxelResource.
## Resource to display.
@export var voxel_resource: VoxelResourceBase:
	set(value):
		voxel_resource = value
		update_configuration_warnings()
		if value:
			populate_mesh()
		else:
			multimesh.instance_count = 0
## Prevents damage to VoxelObject
@export var invulnerable = false
## Darken damaged voxels.
@export var darkening = true
@export_subgroup("Debris")
## Type of debris generated [br]
## None: No debris will be generated [br]
## Multimesh: Debri has limited physics and no collision [br]
## Rigid body: Debris are made up of rigid bodies, heavy performance reduction [br]
@export_enum("None", "Multimesh", "Rigid Bodies") var debris_type = 0
## Strenght of gravity on debris
@export var debris_weight = 1
## Chance of generating debris per destroyed voxel
@export_range(0, 1, .1) var debris_density = .2
## Time in seconds before debris are deleted
@export var debris_lifetime = 5
@export_subgroup("Dithering")
## Maximum amount of darkening.
@export_range(0, .20, .01) var dark_dithering = 0.0:
	set(value):
		dark_dithering = value
		populate_mesh()
## Maximum amount of lightening.
@export_range(0, .20, .01) var light_dithering = 0.0:
	set(value):
		light_dithering = value
		populate_mesh()
## Ratio of darkening to lightening.
@export_range(0, 1, .1) var dithering_bias = 0.5:
	set(value):
		dithering_bias = value
		populate_mesh()
## Seed used when choosing if a voxel is lightened or darkened.
@export var dithering_seed: int = 0:
	set(value):
		dithering_seed = value
		populate_mesh()


## Runs on node start
func _ready() -> void:
	if not Engine.is_editor_hint():
		if not voxel_resource:
			push_warning("Voxel object has no VoxelResource")
			return
		
		# Preload rigid body debris 
		if debris_type == 2:
			voxel_resource.pool_rigid_bodies(min(voxel_resource.vox_count, 1000))
		
		# Add to server
		VoxelServer.voxel_objects.append(self)
		VoxelServer.total_active_voxels += voxel_resource.vox_count
		
		# Add shapes
		voxel_resource.buffer("colors")
		voxel_resource.buffer("color_index")
		var static_body = StaticBody3D.new()
		add_child(static_body)
		for shape_info in voxel_resource.starting_shapes:
			var shape_node = CollisionShape3D.new()
			var shape = BoxShape3D.new()
			shape_node.shape = shape
			shape.extents = shape_info["extents"]
			static_body.add_child(shape_node)
			shape_node.position = shape_info["position"]
		
		# Updated colors if dithered.
		for i in multimesh.instance_count:
			var color = multimesh.get_instance_color(i)
			if color not in voxel_resource.colors:
				voxel_resource.colors.append(color)
			voxel_resource.color_index[i] = voxel_resource.colors.find(color)


## Creates multimesh from the VoxelResource
func populate_mesh() -> void:
	if voxel_resource and Engine.is_editor_hint():
		# Buffers vars to prevent performence drop 
		# when finding vox color/position
		voxel_resource.buffer("positions")
		voxel_resource.buffer("color_index")
		voxel_resource.buffer("colors")
		
		# Create multimesh
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.instance_count = voxel_resource.vox_count
		
		# Create mesh
		var mesh = BoxMesh.new()
		mesh.material = preload("res://addons/VoxelDestruction/Resources/voxel_material.tres")
		mesh.size = voxel_resource.vox_size
		multimesh.mesh = mesh
		
		# Set dithering seed
		var random = RandomNumberGenerator.new()
		random.set_seed(dithering_seed)
		
		# Dither voxels and populate multimesh
		for i in multimesh.instance_count:
			var dark_variation = random.randf_range(0, dark_dithering)
			var light_variation = random.randf_range(0, light_dithering)
			var dithered_color = Color.WHITE
			if dark_dithering == 0 or light_dithering == 0:
				if dark_dithering == 0:
					dithered_color = get_vox_color(i).lightened(light_variation)
				elif light_dithering == 0:
					dithered_color = get_vox_color(i).darkened(dark_variation)
			else:
				dithered_color = get_vox_color(i).darkened(dark_variation) if randf() > dithering_bias else get_vox_color(i).lightened(light_variation)
			multimesh.set_instance_transform(i, Transform3D(Basis(), voxel_resource.positions[i]*voxel_resource.vox_size))
			multimesh.set_instance_color(i, dithered_color)


## Returns vox color
func get_vox_color(voxid: int) -> Color:
	voxel_resource.buffer("colors")
	voxel_resource.buffer("color_index")
	return voxel_resource.colors[voxel_resource.color_index[voxid]]


## Damage voxels
func damage_voxels(damager: VoxelDamager, voxel_count: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array) -> void:
	# record damage results and create task pool
	var damage_results: Array
	damage_results.resize(voxel_count)
	var group_id = WorkerThreadPool.add_group_task(
		_damage_voxel.bind(voxel_positions, global_voxel_positions, damager, damage_results), 
		voxel_count, -1, false, "Calculating Voxel Damage"
	)
	while not WorkerThreadPool.is_group_task_completed(group_id):
		voxel_resource.buffer("health")
		voxel_resource.buffer("positions_dict")
		await get_tree().process_frame
	await _apply_damage_results(damage_results)


func _damage_voxel(voxel: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array, damager: VoxelDamager, damage_results: Array) -> void:
	# Get positions and vox_ids to modify later and calculate damage
	var vox_position: Vector3 = global_voxel_positions[voxel]
	var vox_pos3i: Vector3i = voxel_positions[voxel]
	var vox_id: int = voxel_resource.positions_dict[vox_pos3i]
	
	# Skip if voxel ID is invalid
	if vox_id == -1:
		return  
	
	var decay: float = damager.global_pos.distance_to(vox_position) / damager.range
	var decay_sample: float = damager.damage_curve.sample(decay)
	
	# Skip processing if damage is negligible
	if decay_sample <= 0.01:
		return
	
	var power_sample: float = damager.power_curve.sample(decay)
	var damage: float = damager.base_damage * decay_sample

	# Compute new voxel health
	var new_health: float = clamp(voxel_resource.health[vox_id] - damage, 0, 100)

	# Store the result in a thread-safe dictionary
	damage_results[voxel] = {"vox_id": vox_id, "health": new_health, "pos": vox_pos3i}


func _apply_damage_results(damage_results: Array) -> void:
	voxel_resource.buffer("positions")
	for result in damage_results:
		# Skip results
		if result == null:
			continue
		var vox_id: int = result["vox_id"]
		var health: float = result["health"]
		var vox_pos3i: Vector3i = result["pos"]
		
		# Set health, darken, remove voxels
		voxel_resource.health[vox_id] = health

		if health > 0:
			if darkening:
				multimesh.set_instance_color(vox_id, get_vox_color(vox_id).darkened(1.0 - (health * 0.01)))
		else:
			# Remove voxel from valid positions
			voxel_resource.valid_positions_dict.erase(vox_pos3i)
			multimesh.set_instance_transform(vox_id, Transform3D())
			VoxelServer.total_active_voxels -= 1


func _regen_collision(chunk_index: Vector3) -> void:
	var chunk := PackedVector3Array()
	var boxes = []
	
	var shapes = []
	for box in boxes:
		var min_pos = box["min"]
		var max_pos = box["max"]
		
		var center = (min_pos + max_pos) * 0.5 * voxel_resource.voxel_size
		var size = ((max_pos - min_pos) + Vector3.ONE) * voxel_resource.voxel_size
		shapes.append({"extents": size * 0.5, "position": center})


func _create_boxes(chunk: PackedVector3Array) -> Array:
	var visited: Dictionary[Vector3, bool]
	var boxes = []

	var can_expand = func(box_min: Vector3, box_max: Vector3, axis: int, pos: int) -> bool:
		var start
		var end
		match axis:
			0: start = Vector3(pos, box_min.y, box_min.z); end = Vector3(pos, box_max.y, box_max.z)
			1: start = Vector3(box_min.x, pos, box_min.z); end = Vector3(box_max.x, pos, box_max.z)
			2: start = Vector3(box_min.x, box_min.y, pos); end = Vector3(box_max.x, box_max.y, pos)

		for x in range(int(start.x), int(end.x) + 1):
			for y in range(int(start.y), int(end.y) + 1):
				for z in range(int(start.z), int(end.z) + 1):
					var check_pos = Vector3(x, y, z)
					if not chunk.has(check_pos) or visited.get(check_pos, false):
						return false
		return true
	
	for pos in chunk:
		if visited.get(pos, false):
			continue
		
		var box_min = pos
		var box_max = pos
		
		# Expand along X, Y, Z greedily
		for axis in range(3):
			while true:
				var next_pos = box_max[axis] + 1
				if can_expand.call(box_min, box_max, axis, next_pos):
					box_max[axis] = next_pos
				else:
					break

		# Mark visited voxels
		for x in range(int(box_min.x), int(box_max.x) + 1):
			for y in range(int(box_min.y), int(box_max.y) + 1):
				for z in range(int(box_min.z), int(box_max.z) + 1):
					visited[Vector3(x, y, z)] = true

		boxes.append({"min": box_min, "max": box_max})

	return boxes
