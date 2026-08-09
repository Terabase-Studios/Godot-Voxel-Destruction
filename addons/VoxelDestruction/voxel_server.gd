@tool
extends Node
class_name voxel_server

const _USE_RUST := true
const _REMOVED_VOXEL_MARKER := Vector3(-1, -7, -7) # Marks empty voxels

## Keeps track of data used in monitors

## Array of [VoxelObject]s
var voxel_objects: Array[VoxelObject]
## Array of [VoxelDamager]s
var voxel_damagers: Array[VoxelDamager]
## Amount of intact voxels
var total_active_voxels: int
## Ammount of shapes used in [VoxelObject]s
var shape_count: int

var _use_gd_ext := false  # Set and used in [VoxelUtilities] to activate GdExtension support


func _ready():
	Performance.add_custom_monitor("Voxel Destruction/Voxel Objects", get_voxel_object_count)
	Performance.add_custom_monitor("Voxel Destruction/Active Voxels", get_voxel_count)
	Performance.add_custom_monitor("Voxel Destruction/Visible Voxels", get_visible_voxel_count)
	Performance.add_custom_monitor("Voxel Destruction/Shape Count", get_shape_count)
	Performance.add_custom_monitor("Voxel Destruction/LOD Hidden Voxels", get_lod_hidden_voxels)
	VoxelUtilities._init_called_from_server()
	_setup_budget()


func _process(_delta: float) -> void:
	_process_queues()


## Returns [member voxel_server.voxel_objects] size
func get_voxel_object_count():    
	return voxel_objects.size()

## Returns [member voxel_server.total_active_voxels]
func get_voxel_count():
	return total_active_voxels

## Returns [VoxelObject]s [member MultiMesh.visible_instance_count]
func get_visible_voxel_count():
	var visible_voxel_count = 0
	for object in voxel_objects:
		visible_voxel_count += object.multimesh.visible_instance_count
	return visible_voxel_count

## Returns [member voxel_server.shape_count]
func get_shape_count():
	return shape_count

## Returns Voxels hidden by [VoxelLODAddon] that would otherwise be visible
func get_lod_hidden_voxels():
	var hidden_voxels: int = 0
	for object in voxel_objects:
		if object.lod_addon:
			hidden_voxels += object.lod_addon.hidden_voxels
	return hidden_voxels

# |--------------------------------------------------|
# |     This is the section for queue budgeting.     |
# | For organizational purposes, all class variables |
# |   and functions related to budgeting live here.  |
# |       Thank you for your understanding. =)       |
# |--------------------------------------------------|

var _target_hz: float = Engine.max_fps
var _frame_budget_pct: float = 0.8 # Use up to 80% of the frame
var _safety_margin_usec: int = 300 # Leave headroom for engine overhead
var _frame_clock: FrameClock # Used to figure out how much time non-VD stuff took
var _budget_ready := false # Wait to process_queues until everything is set
var _target_usec := int((1.0 / _target_hz) * 1_000_000) # Target usec for budgeting
var viewport_rid: RID # Get rendering costs
#var _last_frame: int # Prevent running two budgets in one frame

func _setup_budget():
	if Engine.is_editor_hint():
		return
	viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true) # Track rendering time
	process_priority = 9999 # Run last to use remaining budget
	_frame_clock = FrameClock.new()
	_frame_clock.name = "FrameClock"
	add_child(_frame_clock)
	#await _frame_clock.ready
	_budget_ready = true


func _process_queues():
	if not _budget_ready:
		return
	#var current_frame = Engine.get_process_frames()
	#if current_frame == _last_frame:
		#return
	#_last_frame = current_frame

	# Get time elapsed in _process so far
	var elapsed: int = Time.get_ticks_usec() - _frame_clock.process_frame_start_usec

	# Get CPU time for rendering last frame
	# a. Retrieve the raw viewport draw CPU time (in milliseconds)
	var viewport_cpu_time = RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
	# b. Fetch the engine's broad rendering setup time (in milliseconds)
	var frame_setup_time = RenderingServer.get_frame_setup_time_cpu()
	# c. Get total frame rendering time on the CPU
	var total_cpu_render_time = viewport_cpu_time + frame_setup_time
	elapsed += total_cpu_render_time

	var budget: int = int(_target_usec * _frame_budget_pct) - elapsed - _safety_margin_usec
	if budget <= 0:
		return

	var remaining := budget

	for voxel_object in voxel_objects:
		if remaining <= 0:
			break
		remaining = _drain_voxel_object(voxel_object, remaining)


func _drain_voxel_object(voxel_object: VoxelObject, remaining_usec: int) -> int:
	const QUEUE_ORDER := [
		&"collision_task_results",  # Creates work for collision_nodes_add / collision_nodes_remove
		&"collision_nodes_add",
		&"collision_nodes_remove",
		&"flood_fill_results", # Creates work for flood_fill_results
		&"collision_dict_snapshot",
		&"damage_task_results",
		&"multimesh_debris",
		&"rigid_body_debris",
		&"flood_fill_apply", # Gives space for other tasks to keep up with the destruction flood-fill causes
	]

	for queue_type in QUEUE_ORDER:
		if remaining_usec <= 0:
			break
		var call_start := Time.get_ticks_usec()
		_dispatch(voxel_object, queue_type, remaining_usec)
		remaining_usec -= Time.get_ticks_usec() - call_start

	return remaining_usec


func _dispatch(voxel_object: VoxelObject, queue_type: StringName, budget_usec: int) -> bool:
	match queue_type:
		&"collision_task_results": return voxel_object._process_collision_task_results(budget_usec)
		&"collision_nodes_add": return voxel_object._process_collision_nodes_add(budget_usec)
		&"collision_nodes_remove": return voxel_object._process_collision_nodes_remove(budget_usec)
		&"flood_fill_results": return voxel_object._process_flood_fill_results(budget_usec)
		&"flood_fill_apply": return voxel_object._process_flood_fill_apply(budget_usec)
		&"collision_dict_snapshot": return voxel_object._process_collision_dict_snapshot()
		&"damage_task_results": return voxel_object._process_damage_task_results(budget_usec)
		&"multimesh_debris": return voxel_object._process_multimesh_debris_creation_queue(budget_usec)
		&"rigid_body_debris": return voxel_object._process_rigid_body_debris_creation_queue(budget_usec)
	return false
