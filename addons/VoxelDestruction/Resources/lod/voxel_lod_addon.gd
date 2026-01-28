@tool
@icon("voxel_lod_addon.svg")
extends Resource
class_name VoxelLODAddon
## Allows for setting LODs for VoxelObjects of varying degrees, drastically reducing rendering costs at set distances by reducing the quality of the model. The LODs drastically reduce the ammount of rendered voxels. However, LODs do not show or take damage. [br]
##
## The [VoxelObject] must be (Re)populated for LOD changes to take affect.

@export_storage var _parent: VoxelObject
@export_storage var _voxel_meshes: Array[VoxelMultiMesh] = []
@export_storage var _default_voxel_mesh: VoxelMultiMesh

## Used to define the strength and activation distance of LODs.
@export var lod_settings: Array[VoxelLODSetting] = []:
	set(value):
		lod_settings = []
		for setting in value:
			if setting:
				lod_settings.append(setting)
				if not setting.is_connected("preview_enabled", _update_preview):
					setting.connect("preview_enabled", _update_preview)
					setting.connect("preview_disabled", _disable_preview)
			else:
				var new_setting = VoxelLODSetting.new()
				new_setting.connect("preview_enabled", _update_preview)
				new_setting.connect("preview_disabled", _disable_preview)
				lod_settings.append(new_setting)
		_update_preview()

## The ammount of hidden voxels that would otherwise be visible during runtime.
var hidden_voxels: int = 0
## Deactivate this LOD and prevent furthar toggling of LODs.
var disabled = false:
	set(value):
		if value:
			_disabled_lod()
		disabled = value

var _current_setting: VoxelLODSetting
var _last_preview: VoxelLODSetting
var _id: int = randi_range(0, 100) % 10


func _init() -> void:
	for setting in lod_settings:
		if not setting:
			push_error("[VD Addon] LOD Setting is NULL! Unexpected behavior may occur!")
			continue
		setting.preview = false
		if not setting.is_connected("preview_enabled", _update_preview):
			setting.connect("preview_enabled", _update_preview)
			setting.connect("preview_disabled", _disable_preview)


func _ready():
	_disabled_lod()
	for setting in lod_settings:
		if not setting:
			return
		setting.activation_range_squared = setting.activation_range * setting.activation_range
	_update_preview()


func _physics_proccess():
	if Engine.is_editor_hint():
		return
	if disabled:
		return
	if Engine.get_physics_frames() % 10 != _id:
		return

	var camera_node = _parent.get_viewport().get_camera_3d()

	var _parent_position = _parent.global_transform.origin
	var camera_position = camera_node.global_transform.origin

	# Calculate the squared distance
	var distance_squared = _parent_position.distance_squared_to(camera_position)

	var dominant_setting: VoxelLODSetting
	for setting in lod_settings:
		if distance_squared > setting.activation_range_squared:
			dominant_setting = setting
	
	if dominant_setting:
		_enable_lod(dominant_setting)
	else:
		_disabled_lod()


func _enable_lod(setting: VoxelLODSetting):
	if not setting:
		return
	if disabled:
		return
	if _parent and setting != _current_setting:
		var new_voxelmesh = _voxel_meshes[lod_settings.find(setting)]
		_parent.multimesh = new_voxelmesh
		_parent._disabled_locks.append("LOD")
		_current_setting = setting
		hidden_voxels = _default_voxel_mesh.visible_instance_count - new_voxelmesh.visible_instance_count


func _disabled_lod():
	if disabled:
		return
	if _parent and _default_voxel_mesh:
		_parent.multimesh = _default_voxel_mesh
		_parent._disabled_locks.pop_at(_parent._disabled_locks.find("LOD"))
		hidden_voxels = 0
		_current_setting = null


func _update_preview():
	if disabled:
		return
	var activated_preview = null
	for setting in lod_settings:
		if not setting:
			push_error("[VD Addon] LOD Setting is NULL! Unexpected behavior may occur!")
			return
		if setting.preview:
			if setting == _last_preview:
				setting.preview = false
			else:
				activated_preview = setting
	_last_preview = activated_preview

	if activated_preview:
		_enable_lod(activated_preview)
	else:
		_disabled_lod()


func _disable_preview():
	if disabled:
		return
	for setting in lod_settings:
		if not setting:
			continue
		if setting.preview:
			return
	_last_preview = null
	_disabled_lod()


## (Re)populate [VoxelMultiMesh]s used for [VoxelLODSetting]s during previews and runtime [br]
## Called when parent [VoxelObject] is (re)populated
func repopulate(delete_old_cache: bool = true):
	_invalidate_cache()
	_default_voxel_mesh = _parent.multimesh
	_voxel_meshes = []
	_parent.voxel_resource.buffer_all()
	for setting in lod_settings:
		var lod_resource = _from_voxel_resource(_parent.voxel_resource, setting.lod_factor)
		setting.voxel_reduction = lod_resource.voxel_reduction * 100
		_voxel_meshes.append(_cache_resource(_populate_mesh(lod_resource), setting, delete_old_cache))
	for setting in lod_settings:
		setting.preview = false


func _from_voxel_resource(original: VoxelResource, lod_factor = 1.5) -> LODVoxelResource:
	var lod = LODVoxelResource.new()

	lod.colors = original.colors.duplicate()
	lod.color_index = PackedByteArray() 
	lod.positions = PackedVector3Array()
	lod.vox_size = original.vox_size * lod_factor
	
	# Loop through original voxels and decimate
	for i in original.vox_count:
		var pos = original.positions[i]
		# Reduce accuracy by dividing by lod_factor and flooring
		var cell = Vector3(
			int(pos.x / lod_factor),
			int(pos.y / lod_factor),
			int(pos.z / lod_factor)
		)

		var lod_pos = cell + Vector3(0.5, 0.5, 0.5)
		
		# Skip duplicates
		if lod.positions.has(lod_pos):
			continue
		
		lod.positions.append(lod_pos)
		lod.color_index.append(original.color_index[i])
	
	_cull_interior_voxels(lod)
	
	lod.vox_count = lod.positions.size()
	lod.voxel_reduction = 1.0 - (float(lod.vox_count)/float(original.vox_count))
	
	return lod


func _cull_interior_voxels(lod: LODVoxelResource) -> void:
	# Build a lookup of occupied cells
	var occupied := {} # Vector3i -> index

	for i in lod.positions.size():
		var p: Vector3 = lod.positions[i]
		var cell := Vector3i(
			int(p.x),
			int(p.y),
			int(p.z)
		)
		occupied[cell] = i

	var new_positions := PackedVector3Array()
	var new_color_index := PackedByteArray()

	var neighbors := [
		Vector3i( 1,  0,  0),
		Vector3i(-1,  0,  0),
		Vector3i( 0,  1,  0),
		Vector3i( 0, -1,  0),
		Vector3i( 0,  0,  1),
		Vector3i( 0,  0, -1),
	]

	for cell in occupied.keys():
		var is_interior := true

		for n in neighbors:
			if not occupied.has(cell + n):
				is_interior = false
				break

		if is_interior:
			continue

		var idx: int = occupied[cell]
		new_positions.append(lod.positions[idx])
		new_color_index.append(lod.color_index[idx])

	lod.positions = new_positions
	lod.color_index = new_color_index
	lod.vox_count = new_positions.size()


func _populate_mesh(lod_resource: LODVoxelResource) -> VoxelMultiMesh:
	if lod_resource:		
		# Create multimesh
		var _multimesh = VoxelMultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh.use_colors = true
		_multimesh.instance_count = lod_resource.vox_count
		_multimesh.create_indexes()
		_multimesh.visible_instance_count = 0
		
		# Create mesh
		var mesh = BoxMesh.new()
		mesh.material = preload("res://addons/VoxelDestruction/Resources/voxel_material.tres")
		mesh.size = lod_resource.vox_size
		_multimesh.mesh = mesh

		
		# Dither voxels and populate multimesh
		for i in _multimesh.instance_count:
			var color = lod_resource.colors[lod_resource.color_index[i]]
			var vox_pos = lod_resource.positions[i]
			_multimesh.set_instance_visibility(i, true)
			_multimesh.voxel_set_instance_transform(i, Transform3D(Basis(), vox_pos*lod_resource.vox_size))
			_multimesh.voxel_set_instance_color(i, color)
		return _multimesh
	return null

@export_storage var _current_cache: Dictionary[VoxelLODSetting, Variant] = {}

func _invalidate_cache():
	var cache_dir := "res://addons/VoxelDestruction/Cache/"
	var path := "%s%s%s%d.tres" % [cache_dir, _parent.name, "LOD", randi_range(1111, 9999)]
	var log_path := cache_dir + "old_cache.txt"
	for indexed_current_cache in _current_cache.values():
		if indexed_current_cache and indexed_current_cache != "" and FileAccess.file_exists(indexed_current_cache):
			var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
			if file == null:
				file = FileAccess.open(log_path, FileAccess.WRITE)

			if file:
				file.seek_end()
				file.store_line(indexed_current_cache)
				file.close()
			else:
				push_error("[VD ADDON] Failed to open old_cache.txt")

func _cache_resource(resource: Resource, setting: VoxelLODSetting, delete_old_cache: bool = true) -> Resource:
	var cache_dir := "res://addons/VoxelDestruction/Cache/"
	var path := "%s%s%s%d.tres" % [cache_dir, _parent.name, "LOD", randi_range(1111, 9999)]
	var log_path := cache_dir + "old_cache.txt"
	if not setting in _current_cache:
		_current_cache[setting] = null
	var indexed_current_cache = _current_cache[setting]

	ResourceSaver.save(resource, path)

	if indexed_current_cache and indexed_current_cache != "" and FileAccess.file_exists(indexed_current_cache):
		var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
		if file == null:
			file = FileAccess.open(log_path, FileAccess.WRITE)

		if file and delete_old_cache:
			file.seek_end()
			file.store_line(indexed_current_cache)
			file.close()
		else:
			push_error("[VD ADDON] Failed to open old_cache.txt")

	_current_cache[setting] = path
	return ResourceLoader.load(path)
