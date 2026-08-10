@tool
@icon("voxel_object.svg")
extends MultiMeshInstance3D
class_name VoxelObject

## Displays and controls a [VoxelResource] or [CompactVoxelResource]. [br]
## [br]
## Must be damaged by calling [method VoxelDamager.hit] on a nearby [VoxelDamager]

#region Declarations 
#region Constants
var _VOXELSTATE_VERSION := 1.0 # Version cross-refrenced with VoxelState to detirmine if auto-populate should happen
const _TIME_BETWEEN_PROCESSING_ATTACKS: float = 0.0 # Time to wait before unfreezing rigid bodies that break off to prevent them colliding with previous collision in the process of being removed
const _STAGGER_APPLY_FLOOD_FILL_RESULTS: = true # Stagger while applying results from flood-fill when flood-fill mode is not disabled or set to destroy
const _STAGGER_APPLY_FLOOD_FILL_RESULTS_SUB = 100 # The amount of voxels to be proccessed before checking functions_budget
const _INITIAL_FLOOD_FILL_RIGID_BODY_FREEZE_TIME = 0.05 # How long RigidBodies created by RigidBody flood-fill mode should be frozen to give time for staggered collision removal to clear the spot.

var _MULTIMESH_DEBRIS_MINIMUM_BATCH_SIZE: int = 10

#endregion
#region Exported Variables
## (Re)populate this object and attatched addons with new voxel data.
@export_tool_button("(Re)populate Mesh") var populate = _populate_mesh
## Resource to display. Use an imported [VoxelResource] or [CompactVoxelResource]
@export var voxel_resource: VoxelResourceBase:
	set(value):
		voxel_resource = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
## Prevents damage to self.
@export var invulnerable = false
## Darken damaged voxels based on voxel health.
@export var darkening = true
## Controls the precision of generated collision shapes.
## Higher values improve accuracy but may increase physics cost.
## Default uses the project setting voxel_destruction/performance/default_collision_quality
@export_enum("Default", "High", "Medium", "Low") var collision_quality = 0
## What the voxel object should do when its health reaches 0. [br]
## [b]Nothing[/b]: Nothing will hapen [br]
## [b]Disable[/b]: Frees as much memory as possible. [br]
## [b]Queue_free()[/b]: Calls queue_free [br]
@export_enum("Nothing", "Disable", "queue_free()") var end_of_life = 1
@export_group("Debris")
## Type of debris generated [br]
## [b]Default[/b]: Default to ProjectSettings "voxel_destruction/performance/collision_preload_percent"[br]
## [b]None[/b]: No debris will be generated [br]
## [b]Multimesh[/b]: Debri has limited physics and no collision [br]
## [b]Rigid body[/b]: Debris are made up of rigid bodies, heavy performance reduction [br]
@export_enum("Default", "None", "Multimesh", "Rigid Bodies") var debris_type = 0
## Strength of gravity on debris
@export var debris_weight = 1.0
## Chance of generating debris per destroyed voxel
@export_range(0, 1, .001) var debris_density = .1
## Time in seconds before debris are deleted
@export var debris_lifetime = 1.0
## Maximum amount of rigid body debris
@export var rigid_body_maximum_debris = 300
@export var rigid_body_pool_debris = false
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
## The amount of debris deployed by the [VoxelObject]
var debris_amount: int = 0
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
var _shapes_to_add: Dictionary[Vector3, Array] = {} # Shapes to be added in physics process
var _shapes_to_remove: Array[Node3D] = [] # Shapes to be removed in physics process
var _damage_tasks: Dictionary = {} # Queue for damaging tasks
var _regen_tasks: Dictionary = {} # Queue for regenerating collision
var _rigid_body_debris_creation_queue: Array = [] # Queue for debris generation
var _multimesh_debris_creation_queue: Array = [] # Queue for debris generation
var _flood_fill_tasks: Dictionary = {} # Queue for flood fill calculations
var _flood_apply_tasks: Array[VoxelFloodApplyTask] = [] # Queue for applying flood-fill
var _positions_dict_snapshot: Dictionary[Vector3i, int] = {} # Used by worker threads to perform thread safe operations
var _shoud_regenerate_positions_dict_snapshot: bool = true # Controls if _physics_process should regenerate _positions_dict_snapshot, set to true after any modification to voxel_resource.positions_dict
var _position_snapshot_locks: Array = [] # Used by worker threads to prevent _positions_dict_snapshot regeneration while performing operations. In main thread: Add unique id to this array and remove it after thread completion.
var _position_snapshot_edits: PackedVector3Array # List of updates to _positions_dict_snapshot
var _position_snapshot_generated := false # Used to decide if _positions_dict_snapshot has been generated and thus should be duplicated from voxel_resource.duplicate()
var _last_hit_pos: Vector3 # Used to run flood fill on last hit pos
var _populating: bool = false # Used to prevent populating more than once at one time
var _last_damage_time: int = -1 # Used to debug the amount of time damaging takes. Measured in milliseconds
var _tweeners := [] # To properly kill all tweeners at cleanup
var _cleaned := false # To tell exit_tree if cleanup was called
var _cleaning := false # Don't want cleanup to run multiple times

#endregion
#region Signals
## Sent when the [VoxelObject] repopulates its Mesh and Collision [br]
## This commonly occurs when (Re)populate Mesh is pressed
signal repopulated
#endregion
#endregion


#region Embedded Classes
# A pending flood-fill result, mid-drain across however many frames it takes.
class VoxelFloodApplyTask extends RefCounted:
	var groups: Array # Reference to detached_groups
	var mode: int # Flood Fill mode
	var scaled_basis: Basis
	var group_idx: int = 0
	var item_idx: int = 0 # Used in deleting voxels in destroy flood-fill mode to kleep track of voxels already deleted
	var chunks_to_regen := PackedVector3Array()
	var debris_queue: Array = []
#endregion


#region Private Functions
func _ready() -> void:
	#region Backwards Compatability
	if not flood_fill:
		flood_fill = 0
	if not collision_quality:
		collision_quality = 0
	#endregion
	if Engine.is_editor_hint():
		# Check for update
		if _voxel_state.version != _VOXELSTATE_VERSION:
			print("[VD ADDON] Updating ", name, "'s VoxelState to new version.")
			_populate_mesh()

		return
		#if multimesh and multimesh.get_reference_count() > 6:
		#	_populate_mesh()
	else:
		if multimesh and multimesh.mesh and multimesh.mesh.surface_get_material(0):
			multimesh.mesh.surface_get_material(0).set_shader_parameter("error", true)
		var _t0 := Time.get_ticks_usec()

		if not _voxel_server:
			push_error("VoxelServer Autoload not found! Please (re)enable the addon")
			_disabled_locks.append("NO VOXEL SERVER")
			print("hey")
			if multimesh and multimesh.mesh and multimesh.mesh.surface_get_material(0):
				multimesh.mesh.surface_get_material(0).set_shader_parameter("error", true)
			return
		if not voxel_resource:
			push_warning("[VD Addon] Missing voxel_resource! ", name)
			_disabled_locks.append("NO VOXEL RESOURCE")
			if multimesh and multimesh.mesh and multimesh.mesh.surface_get_material(0):
				multimesh.mesh.surface_get_material(0).set_shader_parameter("error", true)
			return
		if not _voxel_state:
			push_warning("[VD Addon] VoxelObject is unpopulated! ", name)
			_disabled_locks.append("NO VOXEL STATE")
			if multimesh and multimesh.mesh and multimesh.mesh.surface_get_material(0):
				multimesh.mesh.surface_get_material(0).set_shader_parameter("error", true)
			return
		if not multimesh or not _voxel_state.unique_voxel_resource:
			push_warning("[VD Addon] VoxelObject's VoxelState is invalid! ", name)
			_disabled_locks.append("NO VOXEL MESH")
			if multimesh and multimesh.mesh and multimesh.mesh.surface_get_material(0):
				multimesh.mesh.surface_get_material(0).set_shader_parameter("error", true)
			return
		if _voxel_state.version != _VOXELSTATE_VERSION:
			push_warning("[VD Addon] VoxelObject's VoxelState is outdated!\nPlease open scene containing this VoxelObject in the editor.\nUnexpected behavior may occur. ", name)
			_disabled_locks.append("OUTDATED VOXEL STATE")
			if multimesh and multimesh.mesh and multimesh.mesh.surface_get_material(0):
				multimesh.mesh.surface_get_material(0).set_shader_parameter("error", true)
			return

		if collision_quality == 0:
			collision_quality = ProjectSettings.get_setting("voxel_destruction/performance/default_collision_quality", 1) + 1
		if debris_type == 0:
			debris_type = ProjectSettings.get_setting("voxel_destruction/debris/default_type", 2) + 1
		if flood_fill == 0:
			flood_fill = ProjectSettings.get_setting("voxel_destruction/other/flood_fill_default", 1) + 1

		health = voxel_resource.vox_count * 100

		voxel_resource = _voxel_state.unique_voxel_resource

		if debris_type == 2 and rigid_body_pool_debris:
			VoxelServer.pool_rigid_bodies(min(voxel_resource.vox_count, 1000))

		VoxelServer.pool_collision_nodes(floor(ProjectSettings.get_setting("voxel_destruction/performance/collision_preload_percent", 0.0) * voxel_resource.vox_count))

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
		add_child(_collision_body, false, Node.INTERNAL_MODE_BACK)

		var shapes_dict = {}
		for shape_info in voxel_resource.starting_shapes:
			var shape_node := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.extents = shape_info["extents"]
			shape_node.shape = shape
			shape_node.position = shape_info["position"]
			_collision_body.add_child(shape_node, false, Node.INTERNAL_MODE_BACK)
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

		if dark_dithering != 0 or light_dithering != 0:
			voxel_resource.buffer("colors")
			voxel_resource.buffer("color_index")
			voxel_resource.colors = _voxel_state.colors
			voxel_resource.color_index = _voxel_state.color_index

		if multimesh and multimesh.mesh and multimesh.mesh.surface_get_material(0):
			multimesh.mesh.surface_get_material(0).set_shader_parameter("error", false)

	if lod_addon:
		lod_addon._ready()


#region Every Physics Frame
func _physics_process(delta):
	#_process_collision_dict_snapshot()
	#_process_flood_fill_results()
	#_process_damage_tasks_results()
	#_process_collison_tasks_to_queue()
	#_process_collision_nodes()
	#_process_multimesh_debris_creation_queue()
	#_process_rigid_body_debris_creation_queue()
	
	
	if Engine.is_editor_hint() and _voxel_state:
		if _voxel_state.version != _VOXELSTATE_VERSION:
			if _populating:
				return
			print("[VD ADDON] Updating ", name, "'s VoxelState to new version.")
			_populate_mesh()
		return

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



#endregion


#region Queue Processing
# Anything budgeted returns true if there is more stuff to process

# Regen _positions_dict_snapshot:
# Unbudgeted
func _process_collision_dict_snapshot():
	if _shoud_regenerate_positions_dict_snapshot and _position_snapshot_locks.is_empty():
		var _position_snapshot_was_just_generated = not _position_snapshot_generated
		_shoud_regenerate_positions_dict_snapshot = false
		if not _position_snapshot_generated:
			_positions_dict_snapshot = voxel_resource.positions_dict.duplicate()
			_position_snapshot_generated = true
		else:
			for edit in _position_snapshot_edits:
				_positions_dict_snapshot.erase(Vector3i(edit))
		_position_snapshot_edits.clear() # Edits applied either way
		# When copy updates we know to now run floodfill 
		# unless _positions_dict_snapshot is generated for the first time
		if flood_fill != -1 and not _position_snapshot_was_just_generated:
			call_deferred("_detach_disconnected_voxels", _last_hit_pos)
	return false


func _process_flood_fill_results(budget_usec: float) -> bool:
	var start := Time.get_ticks_usec()
	for task in _flood_fill_tasks:
		if WorkerThreadPool.is_task_completed(task):
			var flood_result: Dictionary = _flood_fill_tasks[task]
			var elapsed := Time.get_ticks_usec() - start
			var remaining_budget := budget_usec - elapsed
			if remaining_budget <= 0.0:
				return true
			#region Queue flood fill task
			var detached_groups = flood_result.get("detached_groups")
			if detached_groups:
				voxel_resource.buffer("positions_dict")
				voxel_resource.buffer("chunks")
				voxel_resource.buffer("vox_chunk_indices")
				var apply_task := VoxelFloodApplyTask.new()
				apply_task.groups = detached_groups
				apply_task.mode = flood_fill
				apply_task.scaled_basis = global_transform.basis.scaled(voxel_resource.vox_size)
				_flood_apply_tasks.append(apply_task)
			#endregion
			_flood_fill_tasks.erase(task)
			_position_snapshot_locks.erase(task)
		if Time.get_ticks_usec() - start >= budget_usec:
			return not _flood_fill_tasks.is_empty()
	return not _flood_fill_tasks.is_empty()


func _process_flood_fill_apply(budget_usec: float) -> bool:
	var start := Time.get_ticks_usec()
	while not _flood_apply_tasks.is_empty():
		var task: VoxelFloodApplyTask = _flood_apply_tasks[0]
		var finished := _flood_apply_task(task, start, budget_usec)
		if finished:
			_flood_apply_tasks.pop_front()
			_finalize_flood_apply_task(task, task.mode != 2)
		if Time.get_ticks_usec() - start >= budget_usec:
			break
	return not _flood_apply_tasks.is_empty()


func _process_damage_task_results(budget_usec: float) -> bool:
	var start := Time.get_ticks_usec()
	for task in _damage_tasks:
		if WorkerThreadPool.is_task_completed(task):
			var damage_results: Array = _damage_tasks[task][0][0]  # unwrap from results
			var damager: VoxelDamager = _damage_tasks[task][1]
			var hit_position: Vector3 = _damage_tasks[task][2]
			_apply_damage_results(damager, damage_results, hit_position)
			_damage_tasks.erase(task)
			# Release _position_snapshot_lock
			_position_snapshot_locks.erase(task)
		if Time.get_ticks_usec() - start >= budget_usec:
			return not _damage_tasks.is_empty()
	return not _damage_tasks.is_empty()


# Finished _regen_tasks are processed and added to _shapes_to_add & _shapes_to_remove
func _process_collision_task_results(budget_usec: float) -> bool:
	var start := Time.get_ticks_usec()
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
				var shape_node = VoxelServer.get_collision_node()
				shape_node.position = shape_data["center"]
				shape_node.shape.extents = shape_data["extents"]
				_shapes_to_add[chunk_index].append(shape_node)
				if chunk_index not in _collision_shapes:
					_collision_shapes[chunk_index] = Array()
				_collision_shapes[chunk_index].append(shape_node)

			if _collision_shapes.has(chunk_index):
				_voxel_server.shape_count += _collision_shapes[chunk_index].size()

			_regen_tasks.erase(task)
		if Time.get_ticks_usec() - start >= budget_usec:
			return not _regen_tasks.is_empty()
	return not _regen_tasks.is_empty()


# Apply shapes to add/remove
func _process_collision_nodes_add(budget_ms: float) -> bool:
	var start := Time.get_ticks_usec()
	var deadline := start + int(budget_ms * 1000.0)

	for chunk_index in _shapes_to_add:
		if Time.get_ticks_usec() >= deadline:
			break

		var shapes_array: Array = _shapes_to_add[chunk_index]
		while not shapes_array.is_empty() and Time.get_ticks_usec() < deadline:
			var shape = shapes_array.pop_back()
			if is_instance_valid(shape):
				# ASSUMPTION: shape may still be attached to a previous owner whose
				# remove_child hasn't executed yet (pooled node reuse race). Resolve
				# parent state at the moment this callback actually runs, not now.
				var target_body := _collision_body
				(func():
					if not is_instance_valid(shape) or not is_instance_valid(target_body):
						return
					var current_parent = shape.get_parent()
					if current_parent == target_body:
						return
					if current_parent:
						current_parent.remove_child(shape)
					target_body.add_child(shape, false, Node.INTERNAL_MODE_BACK)
				).call_deferred()

		if shapes_array.is_empty():
			_shapes_to_add.erase(chunk_index)

	return not _shapes_to_add.is_empty()


func _process_collision_nodes_remove(budget_ms: float) -> bool:
	var start := Time.get_ticks_usec()
	var deadline := start + int(budget_ms * 1000.0)

	while not _shapes_to_remove.is_empty() and Time.get_ticks_usec() < deadline:
		var shape = _shapes_to_remove.pop_back()
		if is_instance_valid(shape):
			# ASSUMPTION: resolve the parent inside the deferred callback (not here)
			# and only hand the node back to the pool once it's actually detached,
			# so a concurrent get_collision_node() can't reuse it mid-flight.
			(func():
				if not is_instance_valid(shape):
					return
				var current_parent = shape.get_parent()
				if current_parent:
					current_parent.remove_child(shape)
				VoxelServer.return_collision_node(shape)
			).call_deferred()

	return not _shapes_to_remove.is_empty()


# Debris task
func _process_multimesh_debris_creation_queue(budget_usec: float) -> bool:
	if _multimesh_debris_creation_queue.is_empty():
		return false

	var start := Time.get_ticks_usec()
	var min_batch := _MULTIMESH_DEBRIS_MINIMUM_BATCH_SIZE

	# We have to have an inital size so I guess the whole queue works
	var max_possible: int = _multimesh_debris_creation_queue.size()

	var gravity_magnitude: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var debri_states := []
	var multi_mesh_instance := MultiMeshInstance3D.new()
	var multi_mesh := MultiMesh.new()
	multi_mesh_instance.top_level = true
	multi_mesh_instance.multimesh = multi_mesh
	multi_mesh.mesh = preload("res://addons/VoxelDestruction/Resources/debri.tres").duplicate()
	multi_mesh.mesh.size = voxel_resource.vox_size
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.instance_count = max_possible  # sized once, never resized below
	add_child(multi_mesh_instance, false, Node.INTERNAL_MODE_BACK)

	var idx := 0
	var consumed := 0
	var _t0 := start
	while (consumed < min_batch or Time.get_ticks_usec() - start < budget_usec) \
			and not _multimesh_debris_creation_queue.is_empty():
		var debris_data = _multimesh_debris_creation_queue.pop_front()
		consumed += 1
		if randf() <= debris_density:  # Control debris density
			var debris_pos = debris_data.pos
			var velocity = (debris_pos - debris_data.origin).normalized() * debris_data.power * -1
			debri_states.append([debris_pos, velocity])
			multi_mesh.set_instance_transform(idx, Transform3D(Basis(), debris_pos))
			idx += 1

	if idx < max_possible:
		multi_mesh.visible_instance_count = idx

	call_deferred("_run_multimesh_debris_lifecycle", multi_mesh, multi_mesh_instance, debri_states, gravity_magnitude)

	return not _multimesh_debris_creation_queue.is_empty()


# Debris task
func _process_rigid_body_debris_creation_queue(budget_usec: float) -> bool:
	if _rigid_body_debris_creation_queue.is_empty():
		return false
	if not voxel_resource:
		_rigid_body_debris_creation_queue.clear()
		return false

	var start := Time.get_ticks_usec()
	var size = voxel_resource.vox_size
	var debris_objects: Array = []

	while Time.get_ticks_usec() - start < budget_usec and not _rigid_body_debris_creation_queue.is_empty():
		var debris_data = _rigid_body_debris_creation_queue.pop_front()

		if randf() > debris_density:
			continue

		# Respect maximum debris
		if rigid_body_maximum_debris != -1 and debris_amount >= rigid_body_maximum_debris:
			_rigid_body_debris_creation_queue.clear()  # No more debris allowed
			break

		# Get debris from pool or create new
		var debri: RigidBody3D
		debri = VoxelServer.get_debri()


		debri.name = "VoxelDebri"
		debri.top_level = true
		debri.show()

		var shape = debri.get_child(0)
		var mesh = debri.get_child(1)

		add_child(debri, true, Node.INTERNAL_MODE_BACK)
		debri.global_position = debris_data.pos
		shape.shape.size = size
		mesh.mesh.size = size

		var velocity = (debris_data.pos - debris_data.origin).normalized() * debris_data.power
		debri.freeze = false
		debri.gravity_scale = debris_weight
		debri.apply_impulse(velocity)

		debris_objects.append(debri)
		debris_amount += 1

	if debris_objects.is_empty():
		return not _rigid_body_debris_creation_queue.is_empty()

	call_deferred("_run_rigid_body_debris_lifecycle", debris_objects)

	return not _rigid_body_debris_creation_queue.is_empty()
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
	_perform_damage_calculation(attack_data)


# Manages _damage_voxel workers.
func _perform_damage_calculation(attack_data: Dictionary) -> void:
	var _t0 := Time.get_ticks_usec()
	var damager: VoxelDamager = attack_data["damager"]
	var voxel_count: int = attack_data["voxel_count"]
	var voxel_positions: PackedVector3Array = attack_data["voxel_positions"]
	var global_voxel_positions: PackedVector3Array = attack_data["global_voxel_positions"]
	var damager_global_pos = attack_data["hit_position"]

	_last_damage_time = Time.get_ticks_msec()
	voxel_resource.buffer("health")
	voxel_resource.buffer("positions_dict")
	voxel_resource.buffer("vox_chunk_indices")
	voxel_resource.buffer("chunks")

	var result = [0]
	var task_id = WorkerThreadPool.add_task(
		func():
			result[0] = VoxelUtilities.calculate_voxels_damage(voxel_count, voxel_positions, 
			voxel_resource.positions_dict, global_voxel_positions, voxel_resource.health, 
			voxel_resource.vox_chunk_indices, voxel_resource.chunks, damager._range, damager.base_damage, 
			damager.damage_curve, damager.base_power, damager.power_curve, damager_global_pos)
	)
	
	_position_snapshot_locks.append(task_id)
	_damage_tasks[task_id] = [result, damager, damager_global_pos]
	# Futher handling of the thread is passed to _physics_process

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
			_position_snapshot_edits.append(vox_pos3i)
			_voxel_server.total_active_voxels -= 1

			var chunk = result["chunk"]
			# Refrence voxel_server class, not the VoxelServer instance
			voxel_resource.chunks[chunk][result["chunk_pos"]] = voxel_server._REMOVED_VOXEL_MARKER

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

	for chunk in chunks_to_regen:
		_regen_collision(chunk)

	if physics:
		_update_physics()

	if (debris_type != 0 or debris_type != 1) and not debris_queue.is_empty() and debris_density > 0:
		if debris_lifetime > 0:
			match debris_type:
				2:
					_create_debri_multimesh(debris_queue)
				3:
					if rigid_body_maximum_debris == -1 or debris_amount <= rigid_body_maximum_debris:
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
	var sample_size := 1
	if collision_quality == 1:
		sample_size = 1
	elif collision_quality == 2:
		sample_size = 2
	elif collision_quality == 3:
		sample_size = 4
	# Create shape nodes
	var task_id = WorkerThreadPool.add_task(
		_create_shapes.bind(chunk, shape_datas, collision_quality),
		false, "Calculating Collision Shapes"
	)
	_regen_tasks[task_id] = [shape_datas, chunk_index]

# This function is undocumented
# WORKER THREAD FUNCTION
func _create_shapes(
	chunk: PackedVector3Array,
	shape_datas: Array,
	collision_downsample: int = 1
) -> void:
	var _t0 := Time.get_ticks_usec()
	var visited: Dictionary[Vector3, bool]
	var boxes = []

	var collision_chunk := PackedVector3Array()
	var chunk_set := {}

	# Downsample collision grid
	if collision_downsample == 1:
		collision_chunk = chunk
	else:
		var downsample_set := {}

		for pos in chunk:
			if pos == voxel_server._REMOVED_VOXEL_MARKER:
				continue

			var collision_pos := Vector3(
				floor(pos.x / collision_downsample),
				floor(pos.y / collision_downsample),
				floor(pos.z / collision_downsample)
			)

			if not downsample_set.has(collision_pos):
				downsample_set[collision_pos] = true
				collision_chunk.append(collision_pos)

	for pos in collision_chunk:
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

	for pos in collision_chunk:
		if visited.get(pos, false):
			continue
		# Refrence voxel_server class, not the VoxelServer instance
		if pos == voxel_server._REMOVED_VOXEL_MARKER:
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

		var min_pos = box_min * collision_downsample
		var max_pos = (box_max + Vector3.ONE) * collision_downsample - Vector3.ONE
		var center = (min_pos + max_pos) * 0.5 * voxel_resource.vox_size
		var extents = ((max_pos - min_pos) + Vector3.ONE) * voxel_resource.vox_size * .5
		boxes.append({"center": center, "extents": extents})
	shape_datas.assign(boxes)
#endregion


#region Debris Handling
func _create_debri_multimesh(debris_queue: Array) -> void:
	_multimesh_debris_creation_queue.append_array(debris_queue)


func _create_debri_rigid_bodies(debris_queue: Array) -> void:
	_rigid_body_debris_creation_queue.append_array(debris_queue)


func _run_multimesh_debris_lifecycle(multi_mesh: MultiMesh, multi_mesh_instance: MultiMeshInstance3D,
		debri_states: Array, gravity_magnitude: float) -> void:
	var current_lifetime = debris_lifetime
	while current_lifetime > 0:
		var delta = get_physics_process_delta_time()
		current_lifetime -= delta
		for i in range(debri_states.size()):
			var data = debri_states[i]
			var velocity: Vector3 = data[1]
			velocity.y -= gravity_magnitude * debris_weight * min(delta, .999) * 2
			data[0] += velocity * delta
			multi_mesh.set_instance_transform(i, Transform3D(Basis(), data[0]))
			data[1] = velocity
		await get_tree().physics_frame
	if is_instance_valid(multi_mesh_instance):
		multi_mesh_instance.queue_free()


func _run_rigid_body_debris_lifecycle(debris_objects: Array) -> void:
	var timer = get_tree().create_timer(debris_lifetime)
	await timer.timeout

	if not debris_objects.is_empty():
		var debris_tween = create_tween()
		_tweeners.append(debris_tween)
		for debri in debris_objects:
			if not is_instance_valid(debri):
				continue
			var shape = debri.get_child(0)
			var mesh = debri.get_child(1)
			debris_tween.parallel().tween_property(shape, "scale", Vector3(0.01, 0.01, 0.01), 1)
			debris_tween.parallel().tween_property(mesh, "scale", Vector3(0.01, 0.01, 0.01), 1)
		await debris_tween.finished

	for debri in debris_objects:
		if not is_instance_valid(debri):
			continue
		var debri_parent = debri.get_parent()
		if debri_parent:
			debri_parent.remove_child(debri)
		debri.scale = Vector3.ONE
		debri.get_child(0).scale = Vector3.ONE
		debri.get_child(1).scale = Vector3.ONE
		VoxelServer.return_debri(debri)
		debris_amount -= 1
#endregion


#region Flood Fill
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
		var groups := []
		groups = VoxelUtilities.flood_fill_groups(_positions_dict_snapshot)

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

func _flood_apply_task(task: VoxelFloodApplyTask, start: int, budget_usec: float) -> bool:
	match task.mode:
		4:
			while task.group_idx < task.groups.size():
				var group = task.groups[task.group_idx]
				task.group_idx += 1
				if not group.is_empty():
					_spawn_voxel_object_chunk(group, task.scaled_basis, task.chunks_to_regen)
					if Time.get_ticks_usec() - start >= budget_usec:
						return task.group_idx >= task.groups.size()
			return true
		3: 
			while task.group_idx < task.groups.size():
				var group = task.groups[task.group_idx]
				task.group_idx += 1
				if not group.is_empty():
					_spawn_falling_chunk(group, task.scaled_basis, task.chunks_to_regen)
					if Time.get_ticks_usec() - start >= budget_usec:
						return task.group_idx >= task.groups.size()
			return true
		_:
			var iterations := 0
			while task.group_idx < task.groups.size():
				var group = task.groups[task.group_idx]
				while task.item_idx < group.size():
					var vox_pos3i = group[task.item_idx]
					task.item_idx += 1
					iterations += 1

					if voxel_resource.positions_dict.has(vox_pos3i):
						var vox_id = voxel_resource.positions_dict[vox_pos3i]
						multimesh.set_instance_visibility(vox_id, false)
						voxel_resource.positions_dict.erase(vox_pos3i)
						_position_snapshot_edits.append(vox_pos3i)
						_voxel_server.total_active_voxels -= 1
						var chunk = voxel_resource.vox_chunk_indices[vox_id]
						var chunk_pos = voxel_resource.chunks[chunk].find(vox_pos3i)
						voxel_resource.chunks[chunk][chunk_pos] = voxel_server._REMOVED_VOXEL_MARKER
						if chunk not in task.chunks_to_regen:
							task.chunks_to_regen.append(chunk)
						health -= voxel_resource.health[vox_id]
						var vt := Transform3D(task.scaled_basis, global_transform.origin)
						var lvc = Vector3(vox_pos3i) + Vector3(0.5, 0.5, 0.5)
						task.debris_queue.append({ "pos": vt * lvc, "origin": Vector3.ZERO, "power": 0 })

					if iterations >= _STAGGER_APPLY_FLOOD_FILL_RESULTS_SUB:
						iterations = 0
						if Time.get_ticks_usec() - start >= budget_usec:
							if debris_type != 0 and not task.debris_queue.is_empty() and debris_density > 0:
								if debris_lifetime > 0:
									match debris_type:
										2:
											_create_debri_multimesh(task.debris_queue)
										3:
											if rigid_body_maximum_debris == -1 or debris_amount <= rigid_body_maximum_debris:
												_create_debri_rigid_bodies(task.debris_queue)
							task.debris_queue.clear()
							return false

				task.item_idx = 0
				task.group_idx += 1
			if debris_type != 0 and not task.debris_queue.is_empty() and debris_density > 0:
				if debris_lifetime > 0:
					match debris_type:
						2:
							_create_debri_multimesh(task.debris_queue)
						3:
							if rigid_body_maximum_debris == -1 or debris_amount <= rigid_body_maximum_debris:
								_create_debri_rigid_bodies(task.debris_queue)
			task.debris_queue.clear()
			return true


func _finalize_flood_apply_task(task: VoxelFloodApplyTask, handle_debris := true) -> void:
	if health <= 0:
		_end_of_life()
		return

	for chunk in task.chunks_to_regen:
		_regen_collision(chunk)
	if physics:
		_update_physics()


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
		_position_snapshot_edits.append(vox_pos3i)
		_voxel_server.total_active_voxels -= 1
		health -= voxel_resource.health[vox_id]
		var chunk_idx = voxel_resource.vox_chunk_indices[vox_id]
		var chunk_pos = voxel_resource.chunks[chunk_idx].find(vox_pos3i)
		# Refrence voxel_server class, not the VoxelServer instance
		voxel_resource.chunks[chunk_idx][chunk_pos] = voxel_server._REMOVED_VOXEL_MARKER
		if chunk_idx not in chunks_to_regen:
			chunks_to_regen.append(chunk_idx)
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
		starting_shapes.append_array(VoxelObjectUtilities.create_shapes(VoxelObjectUtilities.create_boxes(chunks[chunk]), vr.vox_size, chunk))

	# Set collision VoxelResource vars
	vr.vox_chunk_indices = vox_chunk_indices
	vr.chunks = chunks
	vr.starting_shapes = starting_shapes
	#endregion

	# Add to scene and position at chunk center
	get_tree().root.add_child(vo, false, Node.INTERNAL_MODE_BACK)
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
	var iterations := 0
	for i in group.size():
		if iterations > _STAGGER_APPLY_FLOOD_FILL_RESULTS_SUB * 2: # Times two because we do twice the voxel iterations
			if _STAGGER_APPLY_FLOOD_FILL_RESULTS:
				await get_tree().physics_frame
			iterations = 0
		else:
			iterations += 1
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
	rb.add_child(mmi, false, Node.INTERNAL_MODE_BACK)

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
	rb.freeze = true
	rb.add_child(col, false, Node.INTERNAL_MODE_BACK)

	# Remove these voxels from the parent VoxelObject
	for vox_pos3i in group:
		if iterations > _STAGGER_APPLY_FLOOD_FILL_RESULTS_SUB * 2:
			if _STAGGER_APPLY_FLOOD_FILL_RESULTS:
				await get_tree().physics_frame
			iterations = 0
		else:
			iterations += 1
		if not voxel_resource.positions_dict.has(vox_pos3i):
			continue
		var vox_id = voxel_resource.positions_dict[vox_pos3i]
		multimesh.set_instance_visibility(vox_id, false)
		voxel_resource.positions_dict.erase(vox_pos3i)
		_position_snapshot_edits.append(vox_pos3i)
		_voxel_server.total_active_voxels -= 1
		health -= voxel_resource.health[vox_id]
		var chunk_idx = voxel_resource.vox_chunk_indices[vox_id]
		var chunk_pos = voxel_resource.chunks[chunk_idx].find(vox_pos3i)
		# Refrence voxel_server class, not the VoxelServer instance
		voxel_resource.chunks[chunk_idx][chunk_pos] = voxel_server._REMOVED_VOXEL_MARKER
		if chunk_idx not in chunks_to_regen:
			chunks_to_regen.append(chunk_idx)

	# Add to scene and position at chunk center
	get_tree().root.add_child(rb, false, Node.INTERNAL_MODE_BACK)
	rb.global_position = center

	# Auto-free after debris_lifetime seconds
	var lifetime = debris_lifetime if debris_lifetime > 0 else 10.0
	get_tree().create_timer(lifetime).timeout.connect(func():
		if is_instance_valid(rb):
			rb.queue_free()
	)

	get_tree().create_timer(_INITIAL_FLOOD_FILL_RIGID_BODY_FREEZE_TIME).timeout.connect(func(): rb.freeze = false )

#endregion


#region Other private funcs
func _populate_mesh() -> void:
	# Using a class here so godot doesn't compile with editor only classes and errors.
	# You would think you could just have it ignore the function, but no. =)
	if Engine.is_editor_hint():
		await VoxelObjectUtilities.populate(self)


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
		var positions = voxel_resource.positions
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
	resource = resource.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
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
	match end_of_life:
		1:
			await cleanup()
		2:
			await cleanup()
			queue_free()


## Call this to prepare the [VoxelObject] for [member Node.queue_free]
func cleanup():
	if _cleaned or _cleaning:
		return
	_cleaning = true
	
	health = 0
	_disabled_locks.append("CLEARED")
	_disabled = true # Physics process will do this on its own but why wait, life is short
	# Handle Addons
	if lod_addon:
		lod_addon._cleanup()
		lod_addon = null
	# Queue removal of all collsion shapes
	for chunk in _collision_shapes:
		_shapes_to_remove.append_array(_collision_shapes[chunk])
	while not _shapes_to_remove.is_empty():
		await get_tree().process_frame
		
	# At this point hard kill, no more nice software dev. >=)
	# Kill tweens
	for tween in _tweeners:
		tween.kill()
	# Stop processing and kill remaining debris
	process_mode = Node.PROCESS_MODE_DISABLED
	for child in get_children(true):
		if "VoxelDebri" in child.name and child is RigidBody3D or MultiMeshInstance3D:
			child.queue_free()
			continue
		if child.process_mode == Node.PROCESS_MODE_INHERIT:
			child.process_mode = process_mode
	# Final clearing of some vars
	_voxel_state = null
	_positions_dict_snapshot.clear()
	_positions_dict_snapshot = {}
	_position_snapshot_edits.clear()
	_position_snapshot_edits = PackedVector3Array()
	for body in _collision_shapes.values():
		if is_instance_valid(body):
			body.queue_free()
	_collision_shapes.clear()
	_collision_shapes = {}
	if is_instance_valid(_collision_body):
		_collision_body.queue_free()
	_collision_body = null
	_shapes_to_add.clear()
	_shapes_to_add = {}
	_shapes_to_remove.clear()
	_shapes_to_remove = []
	_damage_tasks.clear()
	_damage_tasks = {}
	_regen_tasks.clear()
	_regen_tasks = {}
	_flood_fill_tasks.clear()
	_flood_fill_tasks = {}
	_flood_apply_tasks.clear()
	_flood_apply_tasks = []
	_rigid_body_debris_creation_queue.clear()
	_rigid_body_debris_creation_queue = []
	_multimesh_debris_creation_queue.clear()
	_multimesh_debris_creation_queue = []
	_position_snapshot_locks.clear()
	_position_snapshot_locks = []
	_last_hit_pos = Vector3.ZERO
	_body_last_transform = Transform3D.IDENTITY
	debris_amount = 0
	health = 0
	multimesh.instance_count = 0
	multimesh = null

	# Sync state with server 
	_voxel_server.total_active_voxels -= voxel_resource.positions_dict.size()
	_voxel_server.voxel_objects.erase(self)
	_voxel_server = null
	# Handle VoxelResource than peace
	if voxel_resource != null and not voxel_resource._cleared:
		voxel_resource._clear()
		voxel_resource = null

	_cleaning = false
	_cleaned = true


# Ran when removed from tree
func _exit_tree():
	if not Engine.is_editor_hint():
		if not _cleaned:
			push_warning("[VD ADDON] Voxel Object <", name, "> did not have | await _cleanup | called!")
#endregion
#endregion

#region Public Functions
## Returns a [AABB] based on the [VoxelResource] in local space.
func get_local_AABB() -> AABB:
	var first_coords := voxel_resource.vox_size / -2
	var second_coords := Vector3(voxel_resource.size) * voxel_resource.vox_size
	return AABB(first_coords, second_coords)
#endregion
