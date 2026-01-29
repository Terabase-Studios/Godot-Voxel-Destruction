@tool
@icon("voxel_object.svg")
extends MultiMeshInstance3D
class_name VoxelObject

## Displays and controls a [VoxelResource] or [CompactVoxelResource]. [br]
## [br]
## Must be damaged by calling [method VoxelDamager.hit] on a nearby [VoxelDamager]

#region Constants
var _COLLISION_NODES_UPDATED_PER_PHYSICS_FRAME: int = ProjectSettings.get_setting("voxel_destruction/performance/collision_nodes_updated_per_physics_frame", 50)
const _TIME_BETWEEN_PROCESSING_ATTACKS: float = 0.05
const _REMOVED_VOXEL_MARKER := Vector3(-1, -7, -7)
#endregion
#region Exported Variables
## (Re)populate this object and attatched addons with new voxel data.
@export_tool_button("(Re)populate Mesh") var populate = _populate_mesh
## Resource to display. Use an imported [VoxelResource] or [CompactVoxelResource]
@export var voxel_resource: VoxelResourceBase:
	set(value):
		voxel_resource = value
		update_configuration_warnings()
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
## [b]Default[/b]: Default to ProjectSettings "voxel_destruction/performance/collision_preload_percent"[br]
## [b]None[/b]: No debris will be generated [br]
## [b]Multimesh[/b]: Debri has limited physics and no collision [br]
## [b]Rigid body[/b]: Debris are made up of rigid bodies, heavy performance reduction [br]
@export_enum("Default", "None", "Multimesh", "Rigid Bodies") var debris_type = 0
## Strength of gravity on debris
@export var debris_weight = 1
## Chance of generating debris per destroyed voxel
@export_range(0, 1, .05) var debris_density = .1
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
@export_subgroup("Material")
@export var use_material: bool = true
@export_subgroup("Physics")
## Acts as a [RigidBody3D]
## @experimental: Clipping is common when damaging the [VoxelObject]
@export var physics = false
## Density for mass calculations. How much one cube meter of voxel weighs in kilograms.
@export var density: float = 1.0
## [PhysicsMaterial] passed down to [member RigidBody3D.physics_material]
@export var physics_material: PhysicsMaterial
@export_subgroup("Experimental")
## @experimental: This property is unstable.
## Remove detached voxels
@export var flood_fill = false

@export_subgroup("Addons")
## Used to reduce rendering costs at varying distances.
@export var lod_addon: VoxelLODAddon:
	set(value):
		if not value:
			lod_addon = null
		else:
			lod_addon = value.duplicate(true)
			lod_addon._parent = self
#endregion
#region Public Variables
## Used to debug the amount of time damaging takes. Measured in milliseconds
var last_damage_time: int = -1
## The ammount of debris deployed by the [VoxelObject]
var debris_ammount: int = 0
## The total health of all voxels
var health: int = 0
#endregion
#region Private Variables
@onready var _voxel_server = get_node("/root/VoxelServer")
var _collision_shapes = Dictionary()
var _collision_body: PhysicsBody3D
var _disabled_locks = []
var _disabled: bool = false
var _body_last_transform: Transform3D
var _attack_queue: Array[Dictionary] = []
var _is_processing: bool = false
var _shapes_to_add: Dictionary[Vector3, Array] = {}
var _shapes_to_remove: Array[Node3D] = []
var _damage_tasks: Dictionary = {}
var _regen_tasks: Dictionary = {}
var _rigid_body_debris_creation_queue: Array = []
var _multimesh_debris_creation_queue: Array = []
var _flood_fill_tasks: Dictionary = {}
var _queue_attacks: bool = ProjectSettings.get_setting("voxel_destruction/performance/queue_attacks", false)

@export_storage var _current_cache: String
#endregion
#region Signals
## Sent when the [VoxelObject] repopulates its Mesh and Collision [br]
## This commonly occurs when (Re)populate Mesh is pressed
signal repopulated
#endregion


func _ready() -> void:
	if Engine.is_editor_hint():
		if multimesh.get_reference_count() > 6:
			#voxel_resource = null
			_populate_mesh(false)
	else:
		if not _voxel_server:
			push_error("VoxelServer Autoload not found! Please (re)enable the addon")
			_voxel_server = voxel_server.new()
			
		if not voxel_resource:
			push_warning("[VD Addon] Missing voxel_resource! ", name)
			_disabled_locks.append("NO VOXEL RESOURCE")
			return
		if not multimesh:
			push_warning("[VD Addon] VoxelObject is unpopulated! ", name)
			_disabled_locks.append("NO VOXEL MULTIMESH")
			return
		if multimesh.get_reference_count() > 8:
			multimesh = multimesh.duplicate(true)

		if debris_type == 0:
			debris_type = ProjectSettings.get_setting("voxel_destruction/debris/default_type", 2) + 1
		health = voxel_resource.vox_count * 100

		voxel_resource = voxel_resource.duplicate(true)

		# Preload rigid body debris (limit to 1000)
		if debris_type == 2:
			voxel_resource.pool_rigid_bodies(min(voxel_resource.vox_count, 1000))

		# Preload collision_nodes
		voxel_resource.pool_collision_nodes(floor(ProjectSettings.get_setting("voxel_destruction/performance/collision_preload_percent", 0.0) * voxel_resource.vox_count))

		# Add to _voxel_server
		_voxel_server.voxel_objects.append(self)
		_voxel_server.total_active_voxels += voxel_resource.vox_count
		_voxel_server.shape_count += voxel_resource.starting_shapes.size()

		# Create collision body
		if not physics:
			_collision_body = StaticBody3D.new()
		else:
			_collision_body = RigidBody3D.new()
			_collision_body.freeze = true
			_collision_body.top_level = true
			_collision_body.global_transform = global_transform
			_collision_body.physics_material_override  = physics_material
			var mass_vector = voxel_resource.vox_count * voxel_resource.vox_size * density
			_collision_body.mass = (mass_vector.x + mass_vector.y + mass_vector.z)/3
			_collision_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			_update_physics()

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
		voxel_resource.materials.clear()

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

	if lod_addon:
		lod_addon._ready()


#region Every Physics Frame
func _physics_process(delta):
	if Engine.is_editor_hint():
		return
	for task in _flood_fill_tasks:
		if WorkerThreadPool.is_task_completed(task):
			var to_remove: Array = _flood_fill_tasks[task]
			_apply_flood_fill_results(to_remove)
			_flood_fill_tasks.erase(task)

	_process_multimesh_debris_creation_queue()
	_process_rigid_body_debris_creation_queue()

	for task in _regen_tasks:
		if WorkerThreadPool.is_task_completed(task):
			var shape_datas: Array = _regen_tasks[task][0]
			var chunk_index: Vector3 = _regen_tasks[task][1]
			# Remove old shapes
			if _collision_shapes.has(chunk_index):
				var old_shapes = _collision_shapes[chunk_index]
				_voxel_server.shape_count -= old_shapes.size()
				for shape in old_shapes:
					_shapes_to_remove.append(shape)
				_collision_shapes[chunk_index].clear()


			# Add shapes and record
			_shapes_to_add[chunk_index] = []
			for shape_data in shape_datas:
				var shape_node = voxel_resource.get_collision_node()
				shape_node.position = shape_data["center"]
				shape_node.shape.extents = shape_data["extents"]
				_shapes_to_add[chunk_index].append(shape_node)
				if chunk_index not in _collision_shapes:
					_collision_shapes[chunk_index] = Array()
				_collision_shapes[chunk_index].append(shape_node)

			if _collision_shapes.has(chunk_index):
				_voxel_server.shape_count += _collision_shapes[chunk_index].size()
			_regen_tasks.erase(task)

	for task in _damage_tasks:
		if WorkerThreadPool.is_group_task_completed(task):
			var damage_results: Array = _damage_tasks[task][0]
			var damager: VoxelDamager = _damage_tasks[task][1]
			_apply_damage_results(damager, damage_results)
			_damage_tasks.erase(task)

	_update_collision_nodes()

	if lod_addon:
		lod_addon._physics_proccess()

	if _disabled_locks.is_empty():
		if _disabled:
			_disabled = false
	else:
		if not _disabled:
			_disabled = true

	if not physics or Engine.is_editor_hint(): return
	if _body_last_transform != _collision_body.transform:
		var new_pos := position
		var new_rot := rotation
		if new_pos.is_finite():
			position = _collision_body.position
		if new_rot.is_finite():
			rotation = _collision_body.rotation
		_body_last_transform = _collision_body.transform


func _update_collision_nodes():
	# Separate budgets
	var add_budget := _COLLISION_NODES_UPDATED_PER_PHYSICS_FRAME
	var remove_budget := _COLLISION_NODES_UPDATED_PER_PHYSICS_FRAME

	# Process adds first
	for chunk_index in _shapes_to_add:
		if add_budget <= 0:
			break

		var shapes_array: Array = _shapes_to_add[chunk_index]
		while add_budget > 0 and not shapes_array.is_empty():
			var shape = shapes_array.pop_back()
			if is_instance_valid(shape):
				_collision_body.call_deferred("add_child", shape)
				add_budget -= 1

		if shapes_array.is_empty():
			_shapes_to_add.erase(chunk_index)

	# Process removes next
	while remove_budget > 0 and not _shapes_to_remove.is_empty():
		var shape = _shapes_to_remove.pop_back()
		if is_instance_valid(shape):
			var shape_parent = shape.get_parent()
			if shape_parent:
				shape_parent.call_deferred("remove_child", shape)
			voxel_resource.call_deferred("return_collision_node", shape)
			remove_budget -= 1
#endregion


#region Voxel Damaging
func _damage_voxels(damager: VoxelDamager, voxel_count: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array) -> void:
	var attack_data := {
		"damager": damager,
		"voxel_count": voxel_count,
		"voxel_positions": voxel_positions,
		"global_voxel_positions": global_voxel_positions
	}
	if _queue_attacks:
		_attack_queue.append(attack_data)
		_process_attack_queue()
	else:
		_perform_damage_calculation(attack_data)


func _process_attack_queue() -> void:
	if _is_processing or _attack_queue.is_empty():
		return

	_is_processing = true
	while not _attack_queue.is_empty():
		var attack_data = _attack_queue.pop_front()
		_perform_damage_calculation(attack_data)
		await get_tree().physics_frame

	_is_processing = false


func _perform_damage_calculation(attack_data: Dictionary) -> void:
	var damager: VoxelDamager = attack_data["damager"]
	var voxel_count: int = attack_data["voxel_count"]
	var voxel_positions: PackedVector3Array = attack_data["voxel_positions"]
	var global_voxel_positions: PackedVector3Array = attack_data["global_voxel_positions"]
	var damager_global_pos = damager.global_position

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
		_damage_voxel.bind(voxel_positions, global_voxel_positions, damager, damager_global_pos, damage_results),
		voxel_count, 1, true, "Calculating Voxel Damage"
	)
	_damage_tasks[group_id] = [damage_results, damager]


func _damage_voxel(voxel: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array, damager: VoxelDamager, damager_global_pos: Vector3, damage_results: Array) -> void:
	# Get positions and vox_ids to modify later and calculate damage
	var vox_position: Vector3 = global_voxel_positions[voxel]
	var vox_pos3i: Vector3i = voxel_positions[voxel]
	var vox_id: int = voxel_resource.positions_dict.get(vox_pos3i, -1)

	# Skip if voxel ID is invalid
	if vox_id == -1:
		return

	var decay: float = damager_global_pos.distance_squared_to(vox_position) / (damager.range * damager.range)
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
	# First loop: identify all voxels that will be destroyed in this damage step.
	# This is done to prevent a destroyed voxel from revealing a neighbor that is also about to be destroyed.
	for result in damage_results:
		# Skip results
		if result == null:
			continue
		if result["health"] <= 0:
			destroyed_voxels.append(result["vox_id"] )

	# Second loop: apply the damage, update health, and handle destruction.
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
				if use_material:
					multimesh.voxel_set_instance_custom_data(vox_id, Color())
		else:
			# Remove voxel from valid positions, chunks, and multimesh
			multimesh.set_instance_visibility(vox_id, false)
			voxel_resource.positions_dict.erase(vox_pos3i)
			_voxel_server.total_active_voxels -= 1

			var chunk = result["chunk"]
			voxel_resource.chunks[chunk][result["chunk_pos"]] = _REMOVED_VOXEL_MARKER

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
		_update_physics()

	if (debris_type != 0 or debris_type != 1) and not debris_queue.is_empty() and debris_density > 0:
		if debris_lifetime > 0 and maximum_debris > 0:
			match debris_type:
				2:
					_create_debri_multimesh(debris_queue)
				3:
					if maximum_debris == -1 or debris_ammount <= maximum_debris:
						_create_debri_rigid_bodies(debris_queue)
	if health <= 0:
		_end_of_life()
		return

	if flood_fill:
		await _detach_disconnected_voxels(damager.global_position)


func _regen_collision(chunk_index: Vector3) -> void:
	_shapes_to_add[chunk_index] = []
	var chunk: PackedVector3Array = voxel_resource.chunks[chunk_index]
	var shape_datas = Array()
	# Create shape nodes
	var task_id = WorkerThreadPool.add_task(
		_create_shapes.bind(chunk, shape_datas),
		false, "Calculating Collision Shapes"
	)
	_regen_tasks[task_id] = [shape_datas, chunk_index]

# This function is undocumented
func _create_shapes(chunk: PackedVector3Array, shape_datas: Array) -> void:
	var visited: Dictionary[Vector3, bool]
	var boxes = []
	var chunk_set := {}
	for pos in chunk:
		chunk_set[pos] = true

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
					if not chunk_set.has(check_pos) or visited.get(check_pos, false):
						return false
		return true

	for pos in chunk:
		if visited.get(pos, false):
			continue
		if pos == _REMOVED_VOXEL_MARKER:
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

		var min_pos = box_min
		var max_pos = box_max
		var center = (min_pos + max_pos) * 0.5 * voxel_resource.vox_size
		var extents = ((max_pos - min_pos) + Vector3.ONE) * voxel_resource.vox_size * .5
		boxes.append({"center": center, "extents": extents})
	shape_datas.assign(boxes)
#endregion


#region Debris Handling
func _create_debri_multimesh(debris_queue: Array) -> void:
	_multimesh_debris_creation_queue.append_array(debris_queue)


func _process_multimesh_debris_creation_queue():
	if _multimesh_debris_creation_queue.is_empty():
		return

	var batch_size = 100 # Create 100 debris per frame
	var current_batch = []
	while len(current_batch) < batch_size and not _multimesh_debris_creation_queue.is_empty():
		current_batch.append(_multimesh_debris_creation_queue.pop_front())

	if current_batch.is_empty():
		return

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
	multi_mesh.instance_count = current_batch.size()
	add_child(multi_mesh_instance)

	# Initialize debris and store physics states
	var idx = 0
	for debris_data in current_batch:
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
	_rigid_body_debris_creation_queue.append_array(debris_queue)


func _process_rigid_body_debris_creation_queue() -> void:
	if _rigid_body_debris_creation_queue.is_empty():
		return

	if not voxel_resource:
		_rigid_body_debris_creation_queue.clear()
		return

	var size = voxel_resource.vox_size
	var debris_objects: Array = []
	var created_count = 0
	var batch_size = 10  # Create 10 debris per frame

	while created_count < batch_size and not _rigid_body_debris_creation_queue.is_empty():
		var debris_data = _rigid_body_debris_creation_queue.pop_front()

		if randf() > debris_density:
			continue

		# Respect maximum debris
		if maximum_debris != -1 and debris_ammount >= maximum_debris:
			_rigid_body_debris_creation_queue.clear() # No more debris allowed
			break

		# Get debris from pool or create new
		var debri: RigidBody3D
		if voxel_resource.debris_pool.is_empty():
			debri = voxel_resource.get_debri()
		else:
			debri = voxel_resource.debris_pool.pop_back()

		debri.name = "VoxelDebri"
		debri.top_level = true
		debri.show()

		# Get children once
		var shape = debri.get_child(0)
		var mesh = debri.get_child(1)

		# Set position and size
		add_child(debri, true, Node.INTERNAL_MODE_BACK)
		debri.global_position = debris_data.pos
		shape.shape.size = size
		mesh.mesh.size = size

		# Launch debris
		var velocity = (debris_data.pos - debris_data.origin).normalized() * debris_data.power
		debri.freeze = false
		debri.gravity_scale = debris_weight
		debri.apply_impulse(velocity)

		# Track active debris
		debris_objects.append(debri)
		debris_ammount += 1
		created_count += 1

	if debris_objects.is_empty():
		return

	# Wait for debris lifetime
	var timer = get_tree().create_timer(debris_lifetime)
	await timer.timeout

	# Tween debris scale down in parallel
	if not debris_objects.is_empty():
		var debris_tween = get_tree().create_tween()
		for debri in debris_objects:
			if not is_instance_valid(debri):
				continue
			var shape = debri.get_child(0)
			var mesh = debri.get_child(1)
			debris_tween.parallel().tween_property(shape, "scale", Vector3(0.01, 0.01, 0.01), 1)
			debris_tween.parallel().tween_property(mesh, "scale", Vector3(0.01, 0.01, 0.01), 1)

		await debris_tween.finished

	# Recycle debris back into pool
	for debri in debris_objects:
		if not is_instance_valid(debri):
			continue

		var debri_parent = debri.get_parent()
		if debri_parent:
			debri_parent.remove_child(debri)
		# Reset scale
		debri.scale = Vector3.ONE
		debri.get_child(0).scale = Vector3.ONE
		debri.get_child(1).scale = Vector3.ONE

		voxel_resource.return_debri(debri)
		debris_ammount -= 1
#endregion


#region Flood Fill
func _flood_fill(to_remove: Array, origin: Vector3i) -> void:
	# Update buffers to ensure current data.
	voxel_resource.buffer("positions")
	voxel_resource.buffer("positions_dict")

	# Retrieve positions dctionar for iteration later.
	var positions_dict = voxel_resource.positions_dict

	var queue = [origin]
	var queue_index = 0  # Points to the current element in the queue.

	var visited = {}
	visited[origin] = true

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


func _detach_disconnected_voxels(start_pos: Vector3 = Vector3.INF) -> void:
	var origin: Vector3i = voxel_resource.origin
	if not start_pos == Vector3.INF:
		var start_pos_local = voxel_resource.world_to_vox(start_pos)
		var offsets = [
			Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
			Vector3i(0, 1, 0), Vector3i(0, -1, 0),
			Vector3i(0, 0, 1), Vector3i(0, 0, -1)
		]
		var found_new_origin = false
		for offset in offsets:
			var neighbor_vox = start_pos_local + offset
			if voxel_resource.positions_dict.has(neighbor_vox):
				origin = neighbor_vox
				found_new_origin = true
				break
		if not found_new_origin:
			if not voxel_resource.positions.is_empty():
				origin = Vector3i(Array(voxel_resource.positions).pick_random())

	if not origin in voxel_resource.positions_dict:
		if not voxel_resource.positions.is_empty():
			voxel_resource.origin = Vector3i(Array(voxel_resource.positions).pick_random())
			origin = voxel_resource.origin
		else:
			return # No voxels left

	voxel_resource.buffer("positions")
	voxel_resource.buffer("positions_dict")
	var to_remove = Array()
	to_remove.resize(voxel_resource.positions.size())
	var task_id = WorkerThreadPool.add_task(
		_flood_fill.bind(to_remove, origin),
		false, "Flood-Fill"
	)
	_flood_fill_tasks[task_id] = to_remove


func _apply_flood_fill_results(to_remove: Array) -> void:
	var scaled_basis := basis.scaled(voxel_resource.vox_size)
	var chunks_to_regen = PackedVector3Array()
	var debris_queue = []

	voxel_resource.buffer("positions_dict")
	voxel_resource.buffer("chunks")
	voxel_resource.buffer("vox_chunk_indices")
	for vox_pos3i in to_remove:
		if not vox_pos3i: break
		var vox_id = voxel_resource.positions_dict[vox_pos3i]
		# Remove voxel from valid positions, chunks, and multimesh
		multimesh.set_instance_visibility(vox_id, false)
		voxel_resource.positions_dict.erase(vox_pos3i)
		_voxel_server.total_active_voxels -= 1

		var chunk = voxel_resource.vox_chunk_indices[vox_id]
		var chunk_pos = voxel_resource.chunks[chunk].find(vox_pos3i)
		voxel_resource.chunks[chunk][chunk_pos] = _REMOVED_VOXEL_MARKER

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
		_update_physics()

	if debris_type != 0 and not debris_queue.is_empty() and debris_density > 0:
		if debris_lifetime > 0 and maximum_debris > 0:
			match debris_type:
				1:
					_create_debri_multimesh(debris_queue)
				2:
					if maximum_debris == -1 or debris_ammount <= maximum_debris:
						_create_debri_rigid_bodies(debris_queue)
#endregion

# Ran on populate, update voxel resource changes here.
func _populate_mesh(delete_old_cache: bool = true) -> void:
	if voxel_resource:
		# Buffers vars to prevent performence drop
		# when finding vox color/position
		voxel_resource.buffer("positions")
		voxel_resource.buffer("color_index")
		voxel_resource.buffer("colors")
		voxel_resource.buffer("visible_voxels")

		multimesh = null

		# Create multimesh
		var _multimesh = VoxelMultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh.use_colors = true
		if use_material:
			_multimesh.use_custom_data = true
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
			var vox_color: Color = _get_vox_color(i)
			if dark_dithering == 0 or light_dithering == 0:
				if dark_dithering == 0:
					dithered_color = vox_color.lightened(light_variation)
				elif light_dithering == 0:
					dithered_color = vox_color.darkened(dark_variation)
			else:
				dithered_color = vox_color.darkened(dark_variation) if randf() > dithering_bias else vox_color.lightened(light_variation)
			var vox_pos = voxel_resource.positions[i]
			if vox_pos in voxel_resource.visible_voxels:
				_multimesh.set_instance_visibility(i, true)
			_multimesh.voxel_set_instance_transform(i, Transform3D(Basis(), vox_pos * voxel_resource.vox_size))
			if use_material:
				_multimesh.voxel_set_instance_custom_data(i, voxel_resource.materials[vox_color])
			_multimesh.voxel_set_instance_color(i, dithered_color.darkened(.1))

		_multimesh = _cache_resource(_multimesh, delete_old_cache)

		#var undo_redo = EditorInterface.get_editor_undo_redo()
		#undo_redo.create_action("Populated Voxel Object")
		#undo_redo.add_do_property(self, &"multimesh", _multimesh)
		#undo_redo.add_undo_property(self, &"multimesh", multimesh)
		#undo_redo.commit_action()
		self.multimesh = _multimesh
		repopulated.emit()
		if lod_addon:
			lod_addon._parent = self
			lod_addon.repopulate(delete_old_cache)

# Utility function that takes a voxid and returns a color
func _get_vox_color(voxid: int) -> Color:
	voxel_resource.buffer("colors")
	voxel_resource.buffer("color_index")
	return voxel_resource.colors[voxel_resource.color_index[voxid]]

# Recalculates center of mass and awakes if [member VoxelObject.physics] is on. [br]
# When the [RigidBody3D] updates it's mass, clipping can occur. [br]
# This function will automatically run when voxels are damaged.
func _update_physics() -> void:
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

# Caches voxel_resource
func _cache_resource(resource: Resource, delete_old_cache: bool = true) -> Resource:
	var cache_dir := "res://addons/VoxelDestruction/Cache/"
	var path := "%s%s%d.tres" % [cache_dir, name, randi_range(1111, 9999)]
	var log_path := cache_dir + "old_cache.txt"

	ResourceSaver.save(resource, path)

	if _current_cache != "" and FileAccess.file_exists(_current_cache):
		var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
		if file == null:
			file = FileAccess.open(log_path, FileAccess.WRITE)

		if file and delete_old_cache:
			file.seek_end()
			file.store_line(_current_cache)
			file.close()
		else:
			push_error("[VD ADDON] Failed to open old_cache.txt")

	_current_cache = path
	return ResourceLoader.load(path)

# Ran when all voxels are destroyed
func _end_of_life() -> void:
	voxel_resource._clear()
	multimesh.instance_count = 0
	match end_of_life:
		1:
			_disabled_locks.append("END OF LIFE")
			_disabled = true
			if lod_addon:
				lod_addon.disabled = true
			multimesh = null
			_voxel_server.voxel_objects.erase(self)
			_voxel_server.total_active_voxels -= voxel_resource.positions_dict.size()
			for key in _collision_shapes:
				_voxel_server.shape_count -= _collision_shapes[key].size()
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

# Ran when removed from tree
func _exit_tree():
	if not Engine.is_editor_hint():
		_voxel_server.voxel_objects.erase(self)
		_voxel_server.total_active_voxels -= voxel_resource.positions_dict.size()
		for key in _collision_shapes:
			_voxel_server.shape_count -= _collision_shapes[key].size()
