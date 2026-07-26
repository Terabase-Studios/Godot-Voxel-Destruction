@tool
@icon("voxel_object.svg")
extends MultiMeshInstance3D
class_name VoxelObject

## Displays and controls a [VoxelResource] or [CompactVoxelResource]. [br]
## [br]
## Must be damaged by calling [method VoxelDamager.hit] on a nearby [VoxelDamager]

#region Declarations 
#region Constants
var _VOXELSTATE_VERSION := 1.0
var _COLLISION_NODES_UPDATED_PER_PHYSICS_FRAME: int = ProjectSettings.get_setting("voxel_destruction/performance/collision_nodes_updated_per_physics_frame", 50)
const _TIME_BETWEEN_PROCESSING_ATTACKS: float = 0.05
const _REMOVED_VOXEL_MARKER := Vector3(-1, -7, -7) # Marks empty voxels
const _STAGGER_APPLY_FLOOD_FILL_RESULTS: = true
var _MULTIMESH_DEBRIS_BATCH_SIZE: int = ProjectSettings.get_setting("voxel_destruction/debris/multimesh/batch_size", 100)
var _RIGID_BODY_DEBRIS_BATCH_SIZE: int = ProjectSettings.get_setting("voxel_destruction/debris/rigid_body/batch_size", 10)

var _BENCHMARK_READY: bool = ProjectSettings.get_setting("voxel_destruction/benchmarks/VoxelObject/benchmark_ready", false)
var _BENCHMARK_DAMAGE: bool = ProjectSettings.get_setting("voxel_destruction/benchmarks/VoxelObject/benchmark_damage", false)
var _BENCHMARK_FLOOD_FILL: bool = ProjectSettings.get_setting("voxel_destruction/benchmarks/VoxelObject/benchmark_flood_fill", false)
var _BENCHMARK_COLLISION: bool = ProjectSettings.get_setting("voxel_destruction/benchmarks/VoxelObject/benchmark_collision", false)
var _BENCHMARK_DEBRIS: bool = ProjectSettings.get_setting("voxel_destruction/benchmarks/VoxelObject/benchmark_debris", false)

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
@export_group("Debris")
## Type of debris generated [br]
## [b]Default[/b]: Default to ProjectSettings "voxel_destruction/performance/collision_preload_percent"[br]
## [b]None[/b]: No debris will be generated [br]
## [b]Multimesh[/b]: Debri has limited physics and no collision [br]
## [b]Rigid body[/b]: Debris are made up of rigid bodies, heavy performance reduction [br]
@export_enum("Default", "None", "Multimesh", "Rigid Bodies") var debris_type = 0
## Strength of gravity on debris
@export var debris_weight = 1
## Chance of generating debris per destroyed voxel
@export_range(0, 1, .001) var debris_density = .1
## Time in seconds before debris are deleted
@export var debris_lifetime = 5
## Maximum ammount of rigid body debris
@export var maximum_debris = 300
@export_group("Dithering")
## Maximum amount of random darkening.
@export_range(0, .20, .01) var dark_dithering = 0.0
## Maximum amount of random lightening.
@export_range(0, .20, .01) var light_dithering = 0.0
## Ratio of random darkening to lightening.
@export_range(0, 1, .1) var dithering_bias = 0.5
## Seed used when choosing if and to what extent a voxel is lightened or darkened.
@export var dithering_seed: int = 0
@export_group("Material")
@export var use_material: bool = true
@export_group("Physics")
## Acts as a [RigidBody3D]
## @experimental: Clipping is common when damaging the [VoxelObject]
@export var physics = false
## Density for mass calculations. How much one cube meter of voxel weighs in kilograms.
@export var density: float = 1.0
## [PhysicsMaterial] passed down to [member RigidBody3D.physics_material]
@export var physics_material: PhysicsMaterial
@export_group("Experimental")
## @experimental: This property is unstable.
## Handle detached voxels [br]
## [b]Default[/b]: Default to ProjectSettings "voxel_destruction/other/flood_fill_default"[br]
## [b]Disabled[/b]: Do not handle detached voxels [br]
## [b]Multimesh[/b]: Detached voxels are destroyed[br]
## [b]Rigid Body[/b]: Detached voxels fall as a rigid body debris and despawns after [member VoxelObject.debris_lifetime][br]
## [b]Voxel Object[/b]: Detached voxels become their own VoxelObject
@export_enum("Default", "Disabled", "Destroy", "Rigid Body", "Voxel Object") var flood_fill = 0
@export_group("Addons")
## Used to reduce rendering costs at varying distances.
@export var lod_addon: VoxelLODAddon:
	set(value):
		if not value:
			lod_addon = null
		else:
			lod_addon = value.duplicate(true)
			lod_addon._parent = self
@export_group("read-only")
## Stores populated voxel data used at runtime.
@export var _voxel_state: VoxelState
#endregion
#region Public Variables
## Used to debug the amount of time damaging takes. Measured in milliseconds
var last_damage_time: int = -1
## The amount of debris deployed by the [VoxelObject]
var debris_ammount: int = 0
## The total health of all voxels
var health: int = 0
#endregion
#region Private Variables
@onready var _voxel_server = get_node("/root/VoxelServer") if not Engine.is_editor_hint() else null # VoxelServer reference
var _collision_shapes = Dictionary() # Collision Shapes
var _collision_body: PhysicsBody3D # Collision Body
var _disabled_locks = [] # Add locks to disable this VoxelObject, all locks must be removed to renable
var _disabled: bool = false # Disables any and all voxel operations at entry points only.
var _body_last_transform: Transform3D # Used in physics to check if the rigid body should be moved
var _attack_queue: Array[Dictionary] = [] # Queue of attacks to process
var _is_processing: bool = false # Controls if a damage task should run if _queue_attacks is true and a task is already running
var _shapes_to_add: Dictionary[Vector3, Array] = {} # Shapes to be added in physics process
var _shapes_to_remove: Array[Node3D] = [] # Shapes to be removed in physics process
var _damage_tasks: Dictionary = {} # Physics process queue for damaging tasks
var _regen_tasks: Dictionary = {} # Physics process queue for regenerating collision
var _rigid_body_debris_creation_queue: Array = [] # Physics process queue for debris generation
var _multimesh_debris_creation_queue: Array = [] # Physics process queue for debris generation
var _flood_fill_tasks: Dictionary = {} # Physics process queue for flood fill calculations
var _queue_attacks: bool = ProjectSettings.get_setting("voxel_destruction/performance/queue_attacks", false) # If attacks should be queued and staggered instead of ran immediately
var _positions_dict_snapshot: Dictionary = {} # Used by worker threads to perform thread safe operations
var _shoud_regenerate_positions_dict_snapshot: bool = true # Controls if _physics_process should regenerate _positions_dict_snapshot, set to true after any modification to voxel_resource.positions_dict
var _position_snapshot_locks: Array = [] # Used by worker threads to prevent _positions_dict_snapshot regeneration while performing operations. In main thread: Add unique id to this array and remove it after thread completion.
var _last_hit_pos: Vector3 # Used to run flood fill on last hit pos
#endregion
#region Signals
## Sent when the [VoxelObject] repopulates its Mesh and Collision [br]
## This commonly occurs when (Re)populate Mesh is pressed
signal repopulated
#endregion
#endregion


func _ready() -> void:
	#region Backwards Compatability
	if not flood_fill:
		flood_fill = 0
	#endregion
	if Engine.is_editor_hint():
		return
		#if multimesh and multimesh.get_reference_count() > 6:
		#	_populate_mesh()
	else:
		var _t0 := Time.get_ticks_usec()

		if not _voxel_server:
			push_error("VoxelServer Autoload not found! Please (re)enable the addon")
			_voxel_server = voxel_server.new()
		if not voxel_resource:
			push_warning("[VD Addon] Missing voxel_resource! ", name)
			_disabled_locks.append("NO VOXEL RESOURCE")
			return
		if not _voxel_state:
			push_warning("[VD Addon] VoxelObject is unpopulated! ", name)
			_disabled_locks.append("NO VOXEL STATE")
			return
		if not multimesh:
			multimesh = _voxel_state.voxel_mesh
			return

		if multimesh.get_reference_count() > 8:
			multimesh = multimesh.duplicate(true)
		if debris_type == 0:
			debris_type = ProjectSettings.get_setting("voxel_destruction/debris/default_type", 2) + 1
		if flood_fill == 0:
			flood_fill = ProjectSettings.get_setting("voxel_destruction/other/flood_fill_default", 1) + 1
		health = voxel_resource.vox_count * 100

		if _BENCHMARK_READY:
			var _t1 := Time.get_ticks_usec()
			print("[VD bench][Ready][", name, "] setup+defaults: %d us" % (_t1 - _t0))
			_t0 = _t1

		voxel_resource = _voxel_state.unique_voxel_resource

		if _BENCHMARK_READY:
			var _t1 := Time.get_ticks_usec()
			print("[VD bench][Ready][", name, "] _voxel_state.unique_voxel_resource: %d us" % (_t1 - _t0))
			_t0 = _t1

		if debris_type == 2:
			voxel_resource.pool_rigid_bodies(min(voxel_resource.vox_count, 1000))

		if _BENCHMARK_READY:
			var _t1 := Time.get_ticks_usec()
			print("[VD bench][Ready][", name, "] pool_rigid_bodies: %d us" % (_t1 - _t0))
			_t0 = _t1

		voxel_resource.pool_collision_nodes(floor(ProjectSettings.get_setting("voxel_destruction/performance/collision_preload_percent", 0.0) * voxel_resource.vox_count))

		if _BENCHMARK_READY:
			var _t1 := Time.get_ticks_usec()
			print("[VD bench][Ready][", name, "] pool_collision_nodes: %d us" % (_t1 - _t0))
			_t0 = _t1

		_voxel_server.voxel_objects.append(self)
		_voxel_server.total_active_voxels += voxel_resource.vox_count
		_voxel_server.shape_count += voxel_resource.starting_shapes.size()

		if not physics:
			_collision_body = StaticBody3D.new()
		else:
			_collision_body = RigidBody3D.new()
			_collision_body.freeze = true
			_collision_body.physics_material_override = physics_material
			var mass_vector = voxel_resource.vox_count * voxel_resource.vox_size * density
			_collision_body.mass = (mass_vector.x + mass_vector.y + mass_vector.z) / 3
			_collision_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			_update_physics()
		add_child(_collision_body)

		if _BENCHMARK_READY:
			var _t1 := Time.get_ticks_usec()
			print("[VD bench][Ready][", name, "] collision body setup: %d us" % (_t1 - _t0))
			_t0 = _t1

		var shapes_dict = {}
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

		if _BENCHMARK_READY:
			var _t1 := Time.get_ticks_usec()
			print("[VD bench][Ready][", name, "] starting_shapes -> CollisionShape3D nodes (%d shapes): %d us" % [shapes_dict.size(), _t1 - _t0])
			_t0 = _t1

		voxel_resource.buffer("visible_voxels")
		voxel_resource.visible_voxels.clear()
		voxel_resource.debuffer("visible_voxels")
		voxel_resource.materials.clear()

		if _BENCHMARK_READY:
			var _t1 := Time.get_ticks_usec()
			print("[VD bench][Ready][", name, "] visible_voxels/materials clear: %d us" % (_t1 - _t0))
			_t0 = _t1

		if dark_dithering != 0 or light_dithering != 0:
			voxel_resource.buffer("colors")
			voxel_resource.buffer("color_index")
			voxel_resource.colors = _voxel_state.colors
			voxel_resource.color_index = _voxel_state.color_index

			if _BENCHMARK_READY:
				var _t1 := Time.get_ticks_usec()
				print("[VD bench][Ready][", name, "] dithering color_index build (%d instances): %d us" % [multimesh.instance_count, _t1 - _t0])
				_t0 = _t1

	if lod_addon:
		lod_addon._ready()


#region Every Physics Frame
func _physics_process(delta):
	if Engine.is_editor_hint():
		return

	# Regen _positions_dict_snapshot:
	if _shoud_regenerate_positions_dict_snapshot and _position_snapshot_locks.is_empty():
		_shoud_regenerate_positions_dict_snapshot = false
		_positions_dict_snapshot = voxel_resource.positions_dict.duplicate()
		# When copy updates we know to now run floodfill
		if flood_fill != -1:
			await _detach_disconnected_voxels(_last_hit_pos)

	# Flood fill tasks
	for task in _flood_fill_tasks:
		if WorkerThreadPool.is_task_completed(task):
			var flood_result: Dictionary = _flood_fill_tasks[task]
			_apply_flood_fill_results(flood_result)
			_flood_fill_tasks.erase(task)
			# Release _position_snapshot_lock
			_position_snapshot_locks.erase(task)

	# Debris tasks
	_process_multimesh_debris_creation_queue()
	_process_rigid_body_debris_creation_queue()

	# Collision regeneration tasks
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

	# Damage tasks
	for task in _damage_tasks:
		if WorkerThreadPool.is_group_task_completed(task):
			var damage_results: Array = _damage_tasks[task][0]
			var damager: VoxelDamager = _damage_tasks[task][1]
			var hit_position: Vector3 = _damage_tasks[task][2]
			_apply_damage_results(damager, damage_results, hit_position)
			_damage_tasks.erase(task)
			# Release _position_snapshot_lock
			_position_snapshot_locks.erase(task)

	# Apply shapes to add/remove
	_update_collision_nodes()

	# Update the addons
	if lod_addon:
		lod_addon._physics_process()

	# Calculate _disabled based apon _disabled locks
	if _disabled_locks.is_empty():
		if _disabled:
			_disabled = false
	else:
		if not _disabled:
			_disabled = true

	# Actual physics
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
# Voxel Damager entry point
func _damage_voxels(damager: VoxelDamager, voxel_count: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array, hit_position: Vector3) -> void:
	var attack_data := {
		"damager": damager,
		"voxel_count": voxel_count,
		"voxel_positions": voxel_positions,
		"global_voxel_positions": global_voxel_positions,
		"hit_position": hit_position
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

# Manages _damage_voxel workers.
func _perform_damage_calculation(attack_data: Dictionary) -> void:
	var _t0 := Time.get_ticks_usec()
	var damager: VoxelDamager = attack_data["damager"]
	var voxel_count: int = attack_data["voxel_count"]
	var voxel_positions: PackedVector3Array = attack_data["voxel_positions"]
	var global_voxel_positions: PackedVector3Array = attack_data["global_voxel_positions"]
	var damager_global_pos = attack_data["hit_position"]

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
		_damage_voxel.bind(voxel_positions, global_voxel_positions, _positions_dict_snapshot, damager, damager_global_pos, damage_results),
		voxel_count, 1, true, "Calculating Voxel Damage"
	)
	_position_snapshot_locks.append(group_id)
	_damage_tasks[group_id] = [damage_results, damager, damager_global_pos]
	# Futher handling of the thread is passed to _physics_process

	if _BENCHMARK_DAMAGE:
		print("[VD bench][Damage][", name, "] _perform_damage_calculation dispatch (%d voxels): %d us" % [voxel_count, Time.get_ticks_usec() - _t0])


# Calculates damage results.
# WORKER THREAD FUNCTION
func _damage_voxel(voxel: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array, vox_positions: Dictionary, damager: VoxelDamager, damager_global_pos: Vector3, damage_results: Array) -> void:
	# Get positions and vox_ids to modify later and calculate damage
	var vox_position: Vector3 = global_voxel_positions[voxel]
	var vox_pos3i: Vector3i = voxel_positions[voxel]
	var vox_id: int = vox_positions.get(vox_pos3i, -1)

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
		"power": power,
	}


# Applies damage, called from physics process.
func _apply_damage_results(damager: VoxelDamager, damage_results: Array, hit_position: Vector3) -> void:
	# Drop late-arriving damage tasks against a dead multimesh.
	if multimesh == null or multimesh.instance_count == 0:
		return
	var _t0 := Time.get_ticks_usec()
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
			debris_queue.append({ "pos": voxel_global_pos, "origin": hit_position, "power": result["power"] })

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

	if _BENCHMARK_DAMAGE:
		print("[VD bench][Damage][", name, "] _apply_damage_results processing (%d results): %d us" % [damage_results.size(), Time.get_ticks_usec() - _t0])

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

	# Regen snapshot for worker threads
	if flood_fill != 1:
		_shoud_regenerate_positions_dict_snapshot = true
		_last_hit_pos = hit_position


func _regen_collision(chunk_index: Vector3) -> void:
	var _t0 := Time.get_ticks_usec()
	_shapes_to_add[chunk_index] = []
	var chunk: PackedVector3Array = voxel_resource.chunks[chunk_index]
	var shape_datas = Array()
	# Create shape nodes
	var task_id = WorkerThreadPool.add_task(
		_create_shapes.bind(chunk, shape_datas),
		false, "Calculating Collision Shapes"
	)
	_regen_tasks[task_id] = [shape_datas, chunk_index]

	if _BENCHMARK_COLLISION:
		print("[VD bench][Collision][", name, "] _regen_collision dispatch (%d voxels): %d us" % [chunk.size(), Time.get_ticks_usec() - _t0])

# This function is undocumented
# WORKER THREAD FUNCTION
func _create_shapes(chunk: PackedVector3Array, shape_datas: Array) -> void:
	var _t0 := Time.get_ticks_usec()
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

	if _BENCHMARK_COLLISION:
		print("[VD bench][Collision][", name, "] _create_shapes (%d voxels -> %d boxes): %d us" % [chunk.size(), boxes.size(), Time.get_ticks_usec() - _t0])
#endregion


#region Debris Handling
func _create_debri_multimesh(debris_queue: Array) -> void:
	_multimesh_debris_creation_queue.append_array(debris_queue)


func _process_multimesh_debris_creation_queue():
	if _multimesh_debris_creation_queue.is_empty():
		return

	var batch_size = _MULTIMESH_DEBRIS_BATCH_SIZE # Create 100 debris per frame
	var current_batch = []
	while len(current_batch) < batch_size and not _multimesh_debris_creation_queue.is_empty():
		current_batch.append(_multimesh_debris_creation_queue.pop_front())

	if current_batch.is_empty():
		return

	var _t0 := Time.get_ticks_usec()
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

	if _BENCHMARK_DEBRIS:
		print("[VD bench][Debris][", name, "] _process_multimesh_debris_creation_queue batch (%d debris): %d us" % [current_batch.size(), Time.get_ticks_usec() - _t0])

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

	var _t0 := Time.get_ticks_usec()
	var size = voxel_resource.vox_size
	var debris_objects: Array = []
	var created_count = 0
	var batch_size = _RIGID_BODY_DEBRIS_BATCH_SIZE  # Create 10 debris per frame

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

	if _BENCHMARK_DEBRIS:
		print("[VD bench][Debris][", name, "] _process_rigid_body_debris_creation_queue batch (%d debris): %d us" % [debris_objects.size(), Time.get_ticks_usec() - _t0])

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

# BFS from origin. Returns a Dictionary mapping voxel -> group_index,
# and populates groups (Array of Arrays of Vector3i).
# The group containing origin is group 0 (the "anchored" group that stays).
# WORKER THREAD FUNCTION
func _flood_fill_groups(positions_dict: Dictionary) -> Array:
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


func _detach_disconnected_voxels(start_pos: Vector3 = Vector3.INF) -> void:
	var _t0 := Time.get_ticks_usec()
	# Resolve the anchor origin — pick a neighbor of the hit point, or fall back to stored origin
	var origin: Vector3i = voxel_resource.origin
	if not start_pos == Vector3.INF:
		# Convert world hit position to local voxel grid coords
		var local_pos := global_transform.affine_inverse() * start_pos
		var start_pos_local := Vector3i(
			int(floor(local_pos.x / voxel_resource.vox_size.x)),
			int(floor(local_pos.y / voxel_resource.vox_size.y)),
			int(floor(local_pos.z / voxel_resource.vox_size.z))
		)
		var offsets = [
			Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
			Vector3i(0, 1, 0), Vector3i(0, -1, 0),
			Vector3i(0, 0, 1), Vector3i(0, 0, -1)
		]
		var found_new_origin = false
		for offset in offsets:
			var nb = start_pos_local + offset
			if voxel_resource.positions_dict.has(nb):
				origin = nb
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
			return

	voxel_resource.buffer("positions")
	voxel_resource.buffer("positions_dict")

	# Run group detection on a thread
	var result = {
		"detached_voxels": null
	}
	# WORKER THREAD FUNC
	var task_callable = func():
		var groups = _flood_fill_groups(_positions_dict_snapshot)
		# Keep the largest group as the anchored structure.
		# Sort descending by size so groups[0] is always the biggest.
		groups.sort_custom(func(a, b): return a.size() > b.size())
		if groups == null or groups.is_empty():
			return

		# Group 0 is the anchored group (contains origin / largest connected mass).
		# All other groups are detached and should fall.
		var anchored_group: Array = groups[0]
		var anchored_set := {}
		for v in anchored_group:
			anchored_set[v] = true

		# Collect all voxels NOT in the anchored group
		var detached_groups: Array = groups.slice(1)
		if detached_groups.is_empty():
			return  # Nothing disconnected — nothing to do
		result["detached_groups"] = detached_groups
	var task_id = WorkerThreadPool.add_task(task_callable, false, "Structural Flood-Fill")
	_position_snapshot_locks.append(task_id)
	_flood_fill_tasks[task_id] = result
	# Futher handling of the thread is passed to _physics_process

	if _BENCHMARK_FLOOD_FILL:
		print("[VD bench][Flood Fill][", name, "] _detach_disconnected_voxels dispatch: %d us" % (Time.get_ticks_usec() - _t0))


func _apply_flood_fill_results(result: Dictionary) -> void:
	var detached_groups = result.get("detached_groups")
	if not detached_groups:
		return

	var _t0 := Time.get_ticks_usec()
	voxel_resource.buffer("positions_dict")
	voxel_resource.buffer("chunks")
	voxel_resource.buffer("vox_chunk_indices")

	var chunks_to_regen := PackedVector3Array()
	var scaled_basis := global_transform.basis.scaled(voxel_resource.vox_size)

	if flood_fill == 4:
		# Spawn each detached group as a falling RigidBody3D with its own MultiMesh
		for group in detached_groups:
			if group.is_empty():
				continue
			_spawn_voxel_object_chunk(group, scaled_basis, chunks_to_regen)
			# Stagger
			if _STAGGER_APPLY_FLOOD_FILL_RESULTS:
				await get_tree().physics_frame

	if flood_fill == 3:
		# Spawn each detached group as a falling RigidBody3D with its own MultiMesh
		for group in detached_groups:
			if group.is_empty():
				continue
			_spawn_falling_chunk(group, scaled_basis, chunks_to_regen)
			# Stagger
			if _STAGGER_APPLY_FLOOD_FILL_RESULTS:
				await get_tree().physics_frame
	else:
		# Original behaviour:  delete detached voxels and spawn debris
		var debris_queue = []
		for group in detached_groups:
			for vox_pos3i in group:
				if not voxel_resource.positions_dict.has(vox_pos3i):
					continue
				var vox_id = voxel_resource.positions_dict[vox_pos3i]
				multimesh.set_instance_visibility(vox_id, false)
				voxel_resource.positions_dict.erase(vox_pos3i)
				_voxel_server.total_active_voxels -= 1
				var chunk = voxel_resource.vox_chunk_indices[vox_id]
				var chunk_pos = voxel_resource.chunks[chunk].find(vox_pos3i)
				voxel_resource.chunks[chunk][chunk_pos] = _REMOVED_VOXEL_MARKER
				if chunk not in chunks_to_regen:
					chunks_to_regen.append(chunk)
				health -= voxel_resource.health[vox_id]
				var vt := Transform3D(scaled_basis, global_transform.origin)
				var lvc = Vector3(vox_pos3i) + Vector3(0.5, 0.5, 0.5)
				debris_queue.append({ "pos": vt * lvc, "origin": Vector3.ZERO, "power": 0 })
			# Stagger
			if _STAGGER_APPLY_FLOOD_FILL_RESULTS:
				await get_tree().physics_frame


		if debris_type != 0 and not debris_queue.is_empty() and debris_density > 0:
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

	for chunk in chunks_to_regen:
		_regen_collision(chunk)

	if physics:
		_update_physics()

	if _BENCHMARK_FLOOD_FILL:
		print("[VD bench][Flood Fill][", name, "] _apply_flood_fill_results processing (%d groups): %d us" % [detached_groups.size(), Time.get_ticks_usec() - _t0])


# TODO: Add material support for voxel chunks
func _spawn_voxel_object_chunk(group: Array, scaled_basis: Basis, chunks_to_regen: PackedVector3Array) -> void:
	if group.is_empty():
		return

	# Precompute some vars
	var group_size = group.size()

	# Calculate center of the chunk in global space for the RigidBody origin
	var vt := Transform3D(scaled_basis, global_transform.origin)
	var center := Vector3.ZERO
	for vox_pos3i in group:
		center += vt * (Vector3(vox_pos3i) + Vector3(0.5, 0.5, 0.5))
	center /= group.size()

	# Calculate center in voxel space
	var local_center := Vector3.ZERO
	for vox in group:
		local_center += Vector3(vox) + Vector3(0.5, 0.5, 0.5)
	local_center /= group.size()

	#region Build a MultiMesh for this chunk
	var chunk_multimesh := VoxelMultiMesh.new()
	chunk_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	chunk_multimesh.use_colors = true
	chunk_multimesh.instance_count = group_size

	# Reuse the same mesh as the parent VoxelObject
	chunk_multimesh.mesh = multimesh.mesh

	# Set instance transforms relative to the chunk center
	# TODO: (CURRENT) Fix voxel mesh generation. Maybe redo.
	for i in group_size:
		var vox_pos: Vector3i = group[i]
		var vox_local := Vector3(vox_pos)
		var local_offset := (vox_local - local_center) * voxel_resource.vox_size

		var vox_id: int = voxel_resource.positions_dict.get(vox_pos, -1)

		chunk_multimesh.set_instance_transform(i, Transform3D(Basis(), local_offset))

		if vox_id >= 0:
			chunk_multimesh.set_instance_color(i, multimesh.get_instance_color(multimesh.induces.get(vox_id, vox_id)))
	#endregion

	#region Create VoxelResource by remaping from original resource (TODO: Multithread)
	var vr := VoxelResource.new()
	vr.vox_count = group_size
	vr.vox_size = voxel_resource.vox_size
	vr.colors = voxel_resource.colors
	vr.chunks = voxel_resource.chunks
	# Resize arrays
	vr.color_index.resize(group_size)
	vr.health.resize(group_size)
	vr.positions.resize(group_size)
	vr.vox_chunk_indices.resize(group_size)
	# TODO: Reintroduce visible voxel culling into new VoxelObject
	vr.visible_voxels
	for i in group_size:
		voxel_resource.buffer_all()
		var vox_id: int = voxel_resource.positions_dict[group[i]]
		var vox_position: Vector3i = voxel_resource.positions[vox_id]
		vr.color_index[i] = voxel_resource.color_index[vox_id]
		vr.health[i] = voxel_resource.health[vox_id]

		var local_pos := Vector3(vox_position) - local_center
		vr.positions[i] = local_pos
		vr.positions_dict[Vector3i(local_pos)] = i
		#vr.positions[i] = Vector3(vox_position)
		#vr.positions_dict[vox_position] = i

		vr.vox_chunk_indices[i] = voxel_resource.vox_chunk_indices[vox_id]
	#endregion
	
	#region Create the VoxelObject with physics
	var vo := VoxelObject.new()
	vo.top_level = true
	vo.density = density
	vo.name = "VoxelObjectChunk"
	vo.multimesh = chunk_multimesh
	vo.voxel_resource = vr

	# Remove these voxels from the parent VoxelObject
	for vox_pos3i in group:
		if not voxel_resource.positions_dict.has(vox_pos3i):
			continue
		var vox_id = voxel_resource.positions_dict[vox_pos3i]
		multimesh.set_instance_visibility(vox_id, false)
		voxel_resource.positions_dict.erase(vox_pos3i)
		_voxel_server.total_active_voxels -= 1
		health -= voxel_resource.health[vox_id]
		var chunk_idx = voxel_resource.vox_chunk_indices[vox_id]
		var chunk_pos = voxel_resource.chunks[chunk_idx].find(vox_pos3i)
		voxel_resource.chunks[chunk_idx][chunk_pos] = _REMOVED_VOXEL_MARKER
	#endregion

	#region Generate collision chunks and shapes
	var chunk_size := Vector3i(16, 16, 16) # Use default chunk size when creating debris. (May be differen from `self`)

	# Sort axes
	var vox_chunk_indices: PackedVector3Array
	var chunks: Dictionary[Vector3, PackedVector3Array]

	# Create voxel dictionary
	for voxel: Vector3i in vr.positions:
		var chunk = Vector3(int(voxel.x/chunk_size.x), int(voxel.y/chunk_size.y), int(voxel.z/chunk_size.z))
		vox_chunk_indices.append(chunk)
		if not chunks.has(chunk):
			chunks[chunk] = PackedVector3Array()
		chunks[chunk].append(voxel)

	# Create collision TODO: MULTITHREAD
	var starting_shapes = Array()
	for chunk in chunks:
		starting_shapes.append_array(VoxImporter.create_shapes(VoxImporter.create_boxes(chunks[chunk]), vr.vox_size, chunk))

	# Set collision VoxelResource vars
	vr.vox_chunk_indices = vox_chunk_indices
	vr.chunks = chunks
	vr.starting_shapes = starting_shapes
	#endregion

	# Add to scene and position at chunk center
	get_tree().root.add_child(vo)
	vo.global_position = center




func _spawn_falling_chunk(group: Array, scaled_basis: Basis, chunks_to_regen: PackedVector3Array) -> void:
	if group.is_empty():
		return

	# Calculate center of the chunk in global space for the RigidBody origin
	var vt := Transform3D(scaled_basis, global_transform.origin)
	var center := Vector3.ZERO
	for vox_pos3i in group:
		center += vt * (Vector3(vox_pos3i) + Vector3(0.5, 0.5, 0.5))
	center /= group.size()

	# Build a MultiMesh for this chunk
	var chunk_multimesh := MultiMesh.new()
	chunk_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	chunk_multimesh.use_colors = true
	chunk_multimesh.instance_count = group.size()

	# Reuse the same mesh as the parent VoxelObject
	chunk_multimesh.mesh = multimesh.mesh

	# Set instance transforms relative to the chunk center
	for i in group.size():
		var vox_pos3i: Vector3i = group[i]
		var vox_global := vt * (Vector3(vox_pos3i))
		var vox_id: int = voxel_resource.positions_dict.get(vox_pos3i, -1)
		var local_offset := vox_global - center
		chunk_multimesh.set_instance_transform(i, Transform3D(Basis(), local_offset))
		if vox_id >= 0:
			chunk_multimesh.set_instance_color(i, multimesh.get_instance_color(multimesh.induces.get(vox_id, vox_id)))

	# Create the RigidBody3D with a single box collision covering the chunk AABB
	var rb := RigidBody3D.new()
	rb.top_level = true
	rb.gravity_scale = debris_weight
	rb.name = "FallingChunk"

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = chunk_multimesh
	mmi.top_level = false
	rb.add_child(mmi)

	# Compute AABB of the chunk for a single collision shape
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for vox_pos3i in group:
		var lv := vt * (Vector3(vox_pos3i) + Vector3(0.5, 0.5, 0.5)) - center
		min_v = min_v.min(lv - voxel_resource.vox_size * 0.5)
		max_v = max_v.max(lv + voxel_resource.vox_size * 0.5)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (max_v - min_v)
	col.shape = box
	col.position = (min_v + max_v) * 0.5
	rb.add_child(col)

	# Remove these voxels from the parent VoxelObject
	for vox_pos3i in group:
		if not voxel_resource.positions_dict.has(vox_pos3i):
			continue
		var vox_id = voxel_resource.positions_dict[vox_pos3i]
		multimesh.set_instance_visibility(vox_id, false)
		voxel_resource.positions_dict.erase(vox_pos3i)
		_voxel_server.total_active_voxels -= 1
		health -= voxel_resource.health[vox_id]
		var chunk_idx = voxel_resource.vox_chunk_indices[vox_id]
		var chunk_pos = voxel_resource.chunks[chunk_idx].find(vox_pos3i)
		voxel_resource.chunks[chunk_idx][chunk_pos] = _REMOVED_VOXEL_MARKER
		#if chunk_idx not in chunks_to_regen:
		#	chunks_to_regen.append(chunk_idx)

	# Add to scene and position at chunk center
	get_tree().root.add_child(rb)
	rb.global_position = center

	# Auto-free after debris_lifetime seconds
	var lifetime = debris_lifetime if debris_lifetime > 0 else 10.0
	get_tree().create_timer(lifetime).timeout.connect(func():
		if is_instance_valid(rb):
			rb.queue_free()
	)
#endregion


func _populate_mesh() -> void:
	if voxel_resource:
		var popup = await VoxelDestructionGodot.create_process("Populating Voxel Mesh", "Preparing")

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

		var new_color_pallet := PackedColorArray()
		var new_colors := PackedByteArray()

		var dithering_enabled := dark_dithering != 0 or light_dithering != 0
		var random: RandomNumberGenerator
		var dark_table: Array[float] = []
		var light_table: Array[float] = []
		if dithering_enabled:
			random = RandomNumberGenerator.new()
			random.set_seed(dithering_seed)
			dark_table = [
				-dark_dithering,
				-dark_dithering * 0.66,
				-dark_dithering * 0.33
			]
			light_table = [
				light_dithering * 0.33,
				light_dithering * 0.66,
				light_dithering
			]

		popup.text = "Creating Multimesh" if not dithering_enabled else "Creating Dithered Multimesh"
		popup.sub_text = "Voxel 0/%d" % [_multimesh.instance_count]
		await popup.redraw()
		var update_step: int = max(1, _multimesh.instance_count / 5)

		# Populate multimesh (with optional dithering) for every voxel
		for i in _multimesh.instance_count:
			if i % update_step == 0:
				popup.progress = float(i) / _multimesh.instance_count
				popup.sub_text = "Voxel %d/%d" % [i, _multimesh.instance_count]
				await popup.redraw()

			var vox_color: Color = _get_vox_color(i)
			var final_color := vox_color

			if dithering_enabled:
				# Pick one of the predefined brightness variations
				var variation := 0.0
				if dark_dithering == 0:
					variation = light_table[random.randi() % light_table.size()]
				elif light_dithering == 0:
					variation = dark_table[random.randi() % dark_table.size()]
				elif random.randf() > dithering_bias:
					variation = dark_table[random.randi() % dark_table.size()]
				else:
					variation = light_table[random.randi() % light_table.size()]
				if variation < 0:
					final_color = vox_color.darkened(-variation)
				else:
					final_color = vox_color.lightened(variation)

			var vox_pos = voxel_resource.positions[i]
			if vox_pos in voxel_resource.visible_voxels:
				_multimesh.set_instance_visibility(i, true)
			_multimesh.voxel_set_instance_transform(
				i, Transform3D(Basis(), vox_pos * voxel_resource.vox_size)
			)
			if use_material:
				_multimesh.voxel_set_instance_custom_data(
					i, voxel_resource.materials[vox_color]
				)
			_multimesh.voxel_set_instance_color(i, final_color)
			if final_color not in new_color_pallet:
				new_color_pallet.append(final_color)
			new_colors.append(new_color_pallet.find(final_color))

		popup.text = "Finishing things up"
		popup.progress = 1.0
		popup.sub_text = "Writing resources"
		await popup.redraw()
		# Make Voxel State
		var new_voxel_state = VoxelState.new()
		new_voxel_state.version = _VOXELSTATE_VERSION
		new_voxel_state.colors = new_color_pallet
		new_voxel_state.color_index = new_colors
		new_voxel_state.voxel_mesh = _multimesh.duplicate(true)
		new_voxel_state.unique_voxel_resource = voxel_resource.duplicate(true)
		new_voxel_state.voxel_mesh.resource_local_to_scene = false
		new_voxel_state.unique_voxel_resource.resource_local_to_scene = false
		_voxel_state = _cache_resource(new_voxel_state)
		#var undo_redo = EditorInterface.get_editor_undo_redo()
		#undo_redo.create_action("Populated Voxel Object")
		#undo_redo.add_do_property(self, &"multimesh", _multimesh)
		#undo_redo.add_undo_property(self, &"multimesh", multimesh)
		#undo_redo.commit_action()
		self.multimesh = _voxel_state.voxel_mesh

		popup.sub_text = "Giving Addons their turn!"
		await popup.redraw()
		if lod_addon:
			lod_addon._parent = self
			lod_addon.repopulate()

		repopulated.emit()
		popup.queue_free()

		# Automatic Cleanup
		#if randf() < .2:
			#await get_tree().physics_frame
			#await VoxelDestructionGodot._clean_cache(get_tree())


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


# Caches resource
func _cache_resource(resource: Resource) -> Resource:
	var cache_dir := "res://addons/VoxelDestruction/User/SavedResources/VoxelObject/"
	
	# Ensure the directory exists on disk
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)

	var unique_id := randi_range(1111, 9999)
	var path := "%s%s_%d.tres" % [cache_dir, name, unique_id]

	# Save resource to path
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("[VD ADDON] Failed to save voxel resource at: %s (Error: %d)" % [path, err])
		return resource

	# Assign path to existing resource in memory instead of reloading from disk
	resource.take_over_path(path)
	return resource


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
							child.process_mode = process_mode
		2:
			queue_free()


# Ran when removed from tree
func _exit_tree():
	if not Engine.is_editor_hint():
		_voxel_server.voxel_objects.erase(self)
		_voxel_server.total_active_voxels -= voxel_resource.positions_dict.size()
		for key in _collision_shapes:
			_voxel_server.shape_count -= _collision_shapes[key].size()
		# Free orphaned collision/debris pool nodes on the queue_free() path.
		if voxel_resource != null and not voxel_resource._cleared:
			voxel_resource._clear()
