@tool
@icon("voxel_object.svg")
extends MultiMeshInstance3D
class_name VoxelObject

## Displays and controls a [VoxelResource] or [CompactVoxelResource].
##
## Must be damaged by calling [method VoxelDamager.hit] on a nearby [VoxelDamager]

@export_tool_button("(Re)populate Mesh") var populate = _populate_mesh
## Resource to display. Use an imported [VoxelResource] or [CompactVoxelResource]
@export var voxel_resource: VoxelResourceBase:
	set(value):
		voxel_resource = value
		update_configuration_warnings()
		if not value:
			multimesh = null
## Prevents damage to self.
@export var invulnerable = false
## Darken damaged voxels based on voxel health.
@export var darkening = true
## What the voxel object should do when its health reaches 0. [br]
## [b]Nothing[/b]: Nothing will hapen [br]
## [b]Disable[/b]: Frees as much memory as possible. [br]
## [b]Queue_free()[/b]: Calls queue_free [br]
@export_enum("nothing", "disable", "queue_free()") var end_of_life = 1
@export_subgroup("Debris")
## Type of debris generated [br]
## [b]None[/b]: No debris will be generated [br]
## [b]Multimesh[/b]: Debri has limited physics and no collision [br]
## [b]Rigid body[/b]: Debris are made up of rigid bodies, heavy performance reduction [br]
@export_enum("None", "Multimesh", "Rigid Bodies") var debris_type = 1
## Strength of gravity on debris
@export var debris_weight = 1
## Chance of generating debris per destroyed voxel
@export_range(0, 1, .1) var debris_density = .2
## Time in seconds before debris are deleted
@export var debris_lifetime = 5
## Maximum ammount of rigid body debris
@export var maximum_debris = 300
@export_subgroup("Dithering")
## Maximum amount of random darkening.
@export_range(0, .20, .01) var dark_dithering = 0.0
## Maximum amount of random lightening.
@export_range(0, .20, .01) var light_dithering = 0.0
## Ratio of random darkening to lightening.
@export_range(0, 1, .1) var dithering_bias = 0.5
## Seed used when choosing if and to what extent a voxel is lightened or darkened.
@export var dithering_seed: int = 0
@export_subgroup("Physics")
## Acts as a [RigidBody3D]
## @experimental: Clipping is common when damaging the [VoxelObject]
@export var physics = false
## Density for mass calculations. How much one cube meter of voxel weighs in kilograms.
@export var density = 1
## [PhysicsMaterial] passed down to [member RigidBody3D.physics_material]
@export var physics_material: PhysicsMaterial
@export_subgroup("Experimental")
## Remove detached voxels
## @experimental: This property is unstable.
@export var flood_fill = false
## Used to debug the amount of time damaging takes. Measured in milliseconds
var last_damage_time: int = -1
## The ammount of debris deployed by the [VoxelObject]
var debris_ammount: int = 0
## The total health of all voxels
@onready var health: int = voxel_resource.vox_count * 100 
var _collision_shapes = Dictionary()
var _collision_body: PhysicsBody3D
var _disabled: bool = false
var _body_last_transform: Transform3D

## Sent when the [VoxelObject] repopulates its Mesh and Collision [br]
## This commonly occurs when (Re)populate Mesh is pressed
signal repopulated

func _ready() -> void:
	if not Engine.is_editor_hint():
		if not voxel_resource:
			push_warning("Voxel object has no VoxelResource")
			return
		
		voxel_resource = voxel_resource.duplicate(true)
		
		# Preload rigid body debris (limit to 1000)
		if debris_type == 2:
			voxel_resource.pool_rigid_bodies(min(voxel_resource.vox_count, 1000))
		
		# Add to VoxelServer
		VoxelServer.voxel_objects.append(self)
		VoxelServer.total_active_voxels += voxel_resource.vox_count
		VoxelServer.shape_count += voxel_resource.starting_shapes.size()
		
		# Create collision body
		if not physics:
			_collision_body = StaticBody3D.new()
		else:
			_collision_body = RigidBody3D.new()
			_collision_body.freeze = true
			_collision_body.physics_material_override  = physics_material
			var mass_vector = voxel_resource.vox_count * voxel_resource.vox_size * density
			_collision_body.mass = (mass_vector.x + mass_vector.y + mass_vector.z)/3
			_collision_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			update_physics()
			
		add_child(_collision_body)
		
		# Create starting shapes
		var shapes_dict = {}  # Cache for _collision_shapes
		for shape_info in voxel_resource.starting_shapes:
			var shape_node := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.extents = shape_info["extents"]
			shape_node.shape = shape
			shape_node.position = shape_info["position"]
			_collision_body.add_child(shape_node)
			
			var chunk = shape_info["chunk"]
			shapes_dict[chunk] = shapes_dict.get(chunk, []) + [shape_node]
		
		if physics:
			_collision_body.freeze = false
		
		_collision_shapes.merge(shapes_dict)
		voxel_resource.starting_shapes.clear()
		voxel_resource.buffer("visible_voxels")
		voxel_resource.visible_voxels.clear()
		voxel_resource.debuffer("visible_voxels")
		
		# Update voxel colors for dithering
		if dark_dithering != 0 or light_dithering != 0:
			voxel_resource.buffer("colors")
			voxel_resource.buffer("color_index")
			var instance_count := multimesh.instance_count
			for i in instance_count:
				var color = multimesh.get_instance_color(i)
				if color not in voxel_resource.colors:
					voxel_resource.colors.append(color)
				voxel_resource.color_index[i] = voxel_resource.colors.find(color)


func _physics_process(delta):
	if not physics or Engine.is_editor_hint(): return
	if _body_last_transform != _collision_body.transform:
		position += _collision_body.position
		rotation += _collision_body.rotation
		_collision_body.position = Vector3.ZERO
		_collision_body.rotation = Vector3.ZERO
		_body_last_transform = _collision_body.transform

## Recalculates center of mass and awakes if [member VoxelObject.physics] is on. [br]
## When the [RigidBody3D] updates it's mass, clipping can occur. [br]
## This function will automatically run when voxels are damaged.
func update_physics() -> void:
	if physics:
		var center := Vector3.ZERO
		var positions = voxel_resource.positions_dict.keys()
		var count: int = positions.size()
		var mass_vector = voxel_resource.vox_count * voxel_resource.vox_size * density
		_collision_body.mass = (mass_vector.x + mass_vector.y + mass_vector.z)/3
		_collision_body.sleeping = false
		for pos in positions:
			center += Vector3(pos)
		center /= count
		center *= voxel_resource.vox_size
		_collision_body.center_of_mass = center


func _populate_mesh() -> void:
	if voxel_resource:
		# Buffers vars to prevent performence drop 
		# when finding vox color/position
		voxel_resource.buffer("positions")
		voxel_resource.buffer("color_index")
		voxel_resource.buffer("colors")
		voxel_resource.buffer("visible_voxels")
		
		# Create multimesh
		var _multimesh = VoxelMultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh.use_colors = true
		_multimesh.instance_count = voxel_resource.vox_count
		_multimesh.create_indexes()
		_multimesh.visible_instance_count = 0
		
		# Create mesh
		var mesh = BoxMesh.new()
		mesh.material = preload("res://addons/VoxelDestruction/Resources/voxel_material.tres")
		mesh.size = voxel_resource.vox_size
		_multimesh.mesh = mesh
		
		# Set dithering seed
		var random = RandomNumberGenerator.new()
		random.set_seed(dithering_seed)
		
		# Dither voxels and populate multimesh
		for i in _multimesh.instance_count:
			var dark_variation = random.randf_range(0, dark_dithering)
			var light_variation = random.randf_range(0, light_dithering)
			var dithered_color = Color.WHITE
			if dark_dithering == 0 or light_dithering == 0:
				if dark_dithering == 0:
					dithered_color = _get_vox_color(i).lightened(light_variation)
				elif light_dithering == 0:
					dithered_color = _get_vox_color(i).darkened(dark_variation)
			else:
				dithered_color = _get_vox_color(i).darkened(dark_variation) if randf() > dithering_bias else _get_vox_color(i).lightened(light_variation)
			var vox_pos = voxel_resource.positions[i]
			if vox_pos in voxel_resource.visible_voxels:
				_multimesh.set_instance_visibility(i, true)
			_multimesh.voxel_set_instance_transform(i, Transform3D(Basis(), vox_pos*voxel_resource.vox_size))
			_multimesh.voxel_set_instance_color(i, dithered_color)
		var undo_redo = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Populated Voxel Object")
		undo_redo.add_do_property(self, &"multimesh", _multimesh)
		undo_redo.add_undo_property(self, &"multimesh", multimesh)
		undo_redo.commit_action()
		repopulated.emit()


func _get_vox_color(voxid: int) -> Color:
	voxel_resource.buffer("colors")
	voxel_resource.buffer("color_index")
	return voxel_resource.colors[voxel_resource.color_index[voxid]]


func _damage_voxels(damager: VoxelDamager, voxel_count: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array) -> void:
	last_damage_time = Time.get_ticks_msec()
	voxel_resource.buffer("health")
	voxel_resource.buffer("positions_dict")
	voxel_resource.buffer("vox_chunk_indices")
	voxel_resource.buffer("chunks")
	# record damage results and create task pool
	var damage_results: Array
	# resize to make modifing thread-safe
	damage_results.resize(voxel_count)
	var group_id = WorkerThreadPool.add_group_task(
		_damage_voxel.bind(voxel_positions, global_voxel_positions, damager, damage_results), 
		voxel_count, -1, false, "Calculating Voxel Damage"
	)
	
	# Wait and buffer
	var last_buffer_time := Time.get_ticks_msec()
	var buffer_interval := 20

	while not WorkerThreadPool.is_group_task_completed(group_id):
		var current_time = Time.get_ticks_msec()
		
		# Buffer only if enough time has passed
		if current_time - last_buffer_time >= buffer_interval:
			voxel_resource.buffer("health")
			voxel_resource.buffer("positions_dict")
			voxel_resource.buffer("vox_chunk_indices")
			voxel_resource.buffer("chunks")
			last_buffer_time = current_time  # Update last buffer time
		
		await get_tree().process_frame  # Allow UI to update
	await _apply_damage_results(damager, damage_results)


func _damage_voxel(voxel: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array, damager: VoxelDamager, damage_results: Array) -> void: 
	# Get positions and vox_ids to modify later and calculate damage
	var vox_position: Vector3 = global_voxel_positions[voxel]
	var vox_pos3i: Vector3i = voxel_positions[voxel]
	var vox_id: int = voxel_resource.positions_dict.get(vox_pos3i, -1)
	
	# Skip if voxel ID is invalid
	if vox_id == -1:
		return  
	
	var decay: float = damager.global_pos.distance_squared_to(vox_position) / (damager.range * damager.range)
	var decay_sample: float = damager.damage_curve.sample(decay)
	
	# Skip processing if damage is negligible
	if decay_sample <= 0.01:
		return
	
	var power_sample: float = damager.power_curve.sample(decay)
	var damage: float = damager.base_damage * decay_sample
	var power: float = damager.base_power * power_sample
	
	# Compute new voxel health
	var new_health: float = clamp(voxel_resource.health[vox_id] - damage, 0, 100)
	
	var chunk = Vector3.ZERO
	var chunk_pos = 0
	if new_health == 0:
		chunk = voxel_resource.vox_chunk_indices[vox_id]
		var chunk_data = voxel_resource.chunks.get(chunk, [])
		chunk_pos = chunk_data.find(vox_pos3i) if chunk_data else -1
	
	# Store the result in a thread-safe dictionary
	damage_results[voxel] = {
		"vox_id": vox_id,
		"health": new_health,
		"pos": vox_pos3i,
		"chunk": chunk,
		"chunk_pos": chunk_pos,
		"power": power
	}


func _apply_damage_results(damager: VoxelDamager, damage_results: Array) -> void:
	voxel_resource.buffer("positions")
	voxel_resource.buffer("positions_dict")
	voxel_resource.buffer("chunks")
	var chunks_to_regen = PackedVector3Array()
	var debris_queue = Array()
	var scaled_basis := basis.scaled(voxel_resource.vox_size)
	# Prevent showing voxels that are queued for destruction
	var destroyed_voxels = PackedInt32Array()
	for result in damage_results:
		# Skip results
		if result == null:
			continue
		if result["health"] <= 0:
			destroyed_voxels.append(result["vox_id"] )
	
	for result in damage_results:
		# Skip results
		if result == null:
			continue
		var vox_id: int = result["vox_id"]
		var vox_health: float = result["health"]
		var vox_pos3i: Vector3i = result["pos"]
		
		# Set health, darken, remove voxels
		health -= voxel_resource.health[vox_id]-vox_health
		voxel_resource.health[vox_id] = vox_health
		if vox_health > 0:
			if darkening:
				multimesh.voxel_set_instance_color(vox_id, _get_vox_color(vox_id).darkened(1.0 - (vox_health * 0.01)))
		else:
			# Remove voxel from valid positions, chunks, and multimesh
			multimesh.set_instance_visibility(vox_id, false)
			voxel_resource.positions_dict.erase(vox_pos3i)
			VoxelServer.total_active_voxels -= 1
			
			var chunk = result["chunk"]
			voxel_resource.chunks[chunk][result["chunk_pos"]] = Vector3(-1, -7, -7)
			
			if chunk not in chunks_to_regen:
				chunks_to_regen.append(chunk)
			
			# Add debri to queue
			# Scale the transform to match the size of each voxel
			var voxel_transform := Transform3D(scaled_basis, transform.origin)
			var local_voxel_centered = Vector3(vox_pos3i) + Vector3(0.5, 0.5, 0.5)
			# Convert to global space using full transform
			var voxel_global_pos = voxel_transform * local_voxel_centered
			debris_queue.append({ "pos": voxel_global_pos, "origin": damager.global_pos, "power": result["power"] }) 
			
			# Show sorounding voxels if necissary
			# Offsets for checking neighbors
			var offsets = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
						   Vector3i(0, 1, 0), Vector3i(0, -1, 0),
						   Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
			
			# Check each neighbor
			for offset in offsets:
				var neighbor = voxel_resource.positions_dict.get(vox_pos3i + offset, false)
				if neighbor and neighbor not in destroyed_voxels:
					multimesh.set_instance_visibility(neighbor, true)
	
	for chunk in chunks_to_regen:
		_regen_collision(chunk)
	
	if physics:
		update_physics()
	
	if debris_type != 0 and not debris_queue.is_empty() and debris_density > 0:
		if debris_lifetime > 0 and maximum_debris > 0:
			match debris_type:
				1:
					_create_debri_multimesh(debris_queue)
				2:
					if maximum_debris == -1 or debris_ammount <= maximum_debris:
						_create_debri_rigid_bodies(debris_queue)
	if health <= 0:
		_end_of_life()
		return
	
	if flood_fill:
		await _detach_disconnected_voxels()


func _regen_collision(chunk_index: Vector3) -> void:
	var chunk: PackedVector3Array = voxel_resource.chunks[chunk_index]
	# Expand shapes to allow thread-safe modification
	var shapes = Array()
	shapes.resize(1000)
	# Create shape nodes
	var task_id = WorkerThreadPool.add_task(
		_create_shapes.bind(chunk, shapes), 
		false, "Calculating Collision Shapes"
	)
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	
	if health <= 0: return
	
	# Remove old shapes
	var old_shapes = _collision_shapes[chunk_index]
	VoxelServer.shape_count -= old_shapes.size()
	for shape in old_shapes:
		shape.queue_free()
	_collision_shapes[chunk_index].clear()
	
	
	# Add shapes and record
	for shape_node in shapes:
		if shape_node == null:
			break
		_collision_body.add_child(shape_node)
		if chunk_index not in _collision_shapes:
			_collision_shapes[chunk_index] = Array()
		_collision_shapes[chunk_index].append(shape_node)
	
	VoxelServer.shape_count += _collision_shapes[chunk_index].size()

# This function is undocumented
func _create_shapes(chunk: PackedVector3Array, shapes) -> void:
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
		if pos == Vector3(-1, -7, -7):
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
	var i = -1
	for box in boxes:
		i += 1
		var min_pos = box["min"]
		var max_pos = box["max"]
		var center = (min_pos + max_pos) * 0.5 * voxel_resource.vox_size
		var shape_node = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape_node.shape = shape
		shape.extents = ((max_pos - min_pos) + Vector3.ONE) * voxel_resource.vox_size * .5
		shape_node.position = center
		shapes[i] = shape_node


func _create_debri_multimesh(debris_queue: Array) -> void:
	# Create MultiMesh
	var gravity_magnitude : float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var debri_states = []
	var multi_mesh_instance = MultiMeshInstance3D.new()
	var multi_mesh = MultiMesh.new()
 
	multi_mesh_instance.top_level = true
	multi_mesh_instance.multimesh = multi_mesh
	multi_mesh.mesh = preload("res://addons/VoxelDestruction/Resources/debri.tres").duplicate()
	multi_mesh.mesh.size = voxel_resource.vox_size
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.instance_count = debris_queue.size()
	add_child(multi_mesh_instance)

	# Initialize debris and store physics states
	var idx = 0
	for debris_data in debris_queue:
		if randf() > debris_density: continue  # Control debris density

		var debris_pos = debris_data.pos
		var velocity = (debris_pos - debris_data.origin).normalized() * debris_data.power * -1

		# Store debris state (position and velocity)
		debri_states.append([debris_pos, velocity])

		# Set the initial position in the MultiMesh
		multi_mesh.set_instance_transform(idx, Transform3D(Basis(), debris_pos))
		idx += 1
	
	# Control debris for the lifetime duration
	var current_lifetime = debris_lifetime
	while current_lifetime > 0:
		
		var delta = get_physics_process_delta_time()
		current_lifetime -= delta

		# Update physics and position of each debris
		for i in range(debri_states.size()):
			var data = debri_states[i]
			var velocity = data[1]
			
			# Apply gravity (affecting the y-axis)
			velocity.y -= gravity_magnitude * debris_weight * min(delta, .999) * 2

			# Update position based on velocity
			data[0] += velocity * delta

			# Update instance transform in MultiMesh
			multi_mesh.set_instance_transform(i, Transform3D(Basis(), data[0]))
			
			# Update velocity for next frame
			data[1] = velocity

		# Yield control to the engine to avoid blocking	
		await get_tree().physics_frame

	# Free the MultiMeshInstance after lifetime expires
	multi_mesh_instance.queue_free()


func _create_debri_rigid_bodies(debris_queue: Array) -> void:
	# Pre-cache children
	var debris_objects = []  # To store all the debris
	var debris_tween = null  # Store the tween for batch processing
	var size = voxel_resource.vox_size

	# Cache debris and set initial properties
	for debris_data in debris_queue:
		if randf() > debris_density:
			continue

		var debri = voxel_resource.get_debri()
		debri.name = "VoxelDebri"
		debri.top_level = true
		debri.show()

		# Retrieve shape and mesh only once for reuse
		var shape = debri.get_child(0)
		var mesh = debri.get_child(1)

		# Set size/position
		add_child(debri, true, Node.INTERNAL_MODE_BACK)
		debri.global_position = debris_data.pos
		shape.shape.size = size
		mesh.mesh.size = size

		# Launch debris with velocity
		var velocity = (debris_data.pos - debris_data.origin).normalized() * debris_data.power
		debri.freeze = false
		debri.gravity_scale = debris_weight
		debri.apply_impulse(velocity)

		# Add to debris objects list
		debris_objects.append(debri)
		debris_ammount += 1

	# Wait for debris lifetime to expire
	var removed_count = false
	var timer = get_tree().create_timer(debris_lifetime)
	while true:
		await get_tree().process_frame
		if timer.time_left <= 0:
			break
		if maximum_debris != -1 and debris_ammount > maximum_debris:
			var wait = randi_range(0, 5)
			for i in range(wait):
				await get_tree().process_frame
			if debris_ammount > maximum_debris:
				removed_count = true
				debris_ammount -= debris_objects.size()
				break

	# Batch scale-down animation
	if not removed_count and not debris_objects.is_empty():
		debris_tween = get_tree().create_tween()

		# Tween all debris in parallel
		for debri in debris_objects:
			var shape = debri.get_child(0)
			var mesh = debri.get_child(1)

			debris_tween.parallel().tween_property(shape, "scale", Vector3(0.01, 0.01, 0.01), 1)
			debris_tween.parallel().tween_property(mesh, "scale", Vector3(0.01, 0.01, 0.01), 1)

		# Wait for the tween to finish
		await get_tree().create_timer(1).timeout

	# Restore debris objects in a batch
	if not voxel_resource: return
	for debri in debris_objects:
		if is_instance_valid(debri):
			debri.get_parent().remove_child(debri)

			# Reset scale of shape and mesh
			debri.get_child(0).scale = Vector3(1, 1, 1)
			debri.get_child(1).scale = Vector3(1, 1, 1)

			# Return debris to the pool
			voxel_resource.debris_pool.append(debri)
	if not removed_count:
		debris_ammount -= debris_objects.size()


func _flood_fill(to_remove: Array) -> void:
	# Update buffers to ensure current data.
	voxel_resource.buffer("positions")
	voxel_resource.buffer("positions_dict")
	
	# Retrieve positions dctionar for iteration later.
	var positions_dict = voxel_resource.positions_dict
	
	var queue = [voxel_resource.origin]
	var queue_index = 0  # Points to the current element in the queue.
	
	var visited = {}
	visited[voxel_resource.origin] = true
	
	# Offsets for the six cardinal directions.
	var offsets = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)
	]
	
	# Perform the flood fill without shifting array elements.
	while queue_index < queue.size():
		var current_vox = queue[queue_index]
		queue_index += 1
		
		for offset in offsets:
			var neighbor_vox = current_vox + offset
			# Only proceed if neighbor has not been visited and exists in positions_dict.
			if not visited.has(neighbor_vox) and positions_dict.has(neighbor_vox):
				visited[neighbor_vox] = true
				queue.append(neighbor_vox)
	
	var index = 0
	for vox: Vector3i in positions_dict.keys():
		if not visited.has(vox):  
			to_remove[index] = vox
			index += 1
	
	positions_dict.clear()
	queue.clear()
	visited.clear()


func _detach_disconnected_voxels() -> void:
	var origin: Vector3i = voxel_resource.origin
	if not voxel_resource.origin in voxel_resource.positions_dict:
		if not voxel_resource.positions.is_empty():
			voxel_resource.origin = Vector3i(Array(voxel_resource.positions).pick_random())
		
	voxel_resource.buffer("positions")
	voxel_resource.buffer("positions_dict")
	var to_remove = Array()
	to_remove.resize(voxel_resource.positions.size())
	var task_id = WorkerThreadPool.add_task(
		_flood_fill.bind(to_remove),
		false, "Flood-Fill"
	)
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	
	var scaled_basis := basis.scaled(voxel_resource.vox_size)
	var chunks_to_regen = PackedVector3Array()
	var debris_queue = Dictionary()
	
	voxel_resource.buffer("positions_dict")
	voxel_resource.buffer("chunks")
	voxel_resource.buffer("vox_chunk_indices")
	for vox_pos3i in to_remove:
		if not vox_pos3i: break
		var vox_id = voxel_resource.positions_dict[vox_pos3i]
		# Remove voxel from valid positions, chunks, and multimesh
		multimesh.set_instance_visibility(vox_id, false)
		voxel_resource.positions_dict.erase(vox_pos3i)
		VoxelServer.total_active_voxels -= 1
		
		var chunk = voxel_resource.vox_chunk_indices[vox_id]
		var chunk_pos = voxel_resource.chunks[chunk].find(vox_pos3i)
		voxel_resource.chunks[chunk][chunk_pos] = Vector3(-1, -7, -7)
			
		if chunk not in chunks_to_regen:
			chunks_to_regen.append(chunk)
		
		health -= voxel_resource.health[vox_id]
		
		# Scale the transform to match the size of each voxel
		var voxel_transform := Transform3D(scaled_basis, transform.origin)
		var local_voxel_centered = Vector3(vox_pos3i) + Vector3(0.5, 0.5, 0.5)
		# Convert to global space using full transform
		var voxel_global_pos = voxel_transform * local_voxel_centered
		debris_queue.append({ "pos": voxel_global_pos, "origin": Vector3.ZERO, "power": 0 }) 
	
	if health <= 0:
		_end_of_life()
		return
	
	for chunk in chunks_to_regen:
		_regen_collision(chunk)
	
	if physics:
		update_physics()
	
	if debris_type != 0 and not debris_queue.is_empty() and debris_density > 0:
		if debris_lifetime > 0 and maximum_debris > 0:
			match debris_type:
				1:
					_create_debri_multimesh(debris_queue)
				2:
					if maximum_debris == -1 or debris_ammount <= maximum_debris:
						_create_debri_rigid_bodies(debris_queue)


func _end_of_life() -> void:
	match end_of_life:
		1:
			_disabled = true
			multimesh = null
			VoxelServer.voxel_objects.erase(self)
			VoxelServer.total_active_voxels -= voxel_resource.positions_dict.size()
			for key in _collision_shapes:
				VoxelServer.shape_count -= _collision_shapes[key].size()
				for shape in _collision_shapes[key]:
					shape.disabled = true
			await get_tree().create_timer(10).timeout
			var proccess_mode = process_mode
			process_mode = Node.PROCESS_MODE_DISABLED
			for key in _collision_shapes:
				for shape in _collision_shapes[key]:
					shape.queue_free()
					_collision_shapes.clear()
					_collision_body.queue_free()
					voxel_resource = null
					for child in get_children(true):
						if "VoxelDebri" in child.name and child is RigidBody3D or MultiMeshInstance3D:
							child.queue_free()
							continue
						if child.process_mode == Node.PROCESS_MODE_INHERIT:
							child.process_mode = proccess_mode
		2:
			queue_free()


func _exit_tree():
	if not Engine.is_editor_hint():
		VoxelServer.voxel_objects.erase(self)
		VoxelServer.total_active_voxels -= voxel_resource.positions_dict.size()
		for key in _collision_shapes:
			VoxelServer.shape_count -= _collision_shapes[key].size()
