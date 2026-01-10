@tool
extends Marker3D
class_name VoxelMarker

const _POSITION_CHANGED_TIMER_SET: float = .5

@export var show_postion_hint_in_editor: bool = true:
	set(value):
		show_postion_hint_in_editor = value
		if value:
			_update_hint()
		else:
			if is_instance_valid(_hint_collision_node):
				remove_child(_hint_collision_node)
				_hint_collision_node.queue_free()
@export var show_postion_hint_during_runtime: bool = true:
	set(value):
		show_postion_hint_during_runtime = value
		if value:
			_update_hint()
		else:
			if is_instance_valid(_hint_collision_node):
				remove_child(_hint_collision_node)
				_hint_collision_node.queue_free()
@export var position_hint_color: Color = Color(1, 0, 0, .5):
	set(value):
		position_hint_color = value
		_update_hint()

var _voxel_scale = Vector3.ZERO
var _position_changed_timer: float = 0.0
var _postition_changed_override: bool = false
var _voxel_coords
var _invalid = false
var _hint_collision_node: MeshInstance3D
var _destroyed: bool = false

func _ready():
	if not Engine.is_editor_hint():
		set_notify_transform(false)
		_update()
		return
	else:
		set_notify_transform(true)
		_update()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		_postition_changed_override = true
		if _position_changed_timer != 0:
			_position_changed_timer = max(0, _position_changed_timer - delta)
			if _position_changed_timer == 0:
				_snap()
	else:
		if not _destroyed and _voxel_coords not in get_parent().voxel_resource.positions_dict:
			print("DESROYED")
			_destroyed = true


func _snap(voxel_scale: Vector3 = _voxel_scale):
	if _invalid:
		return
	var pos = position
	position = Vector3(
		round(pos.x / voxel_scale.x) * voxel_scale.x,
		round(pos.y / voxel_scale.y) * voxel_scale.y,
		round(pos.z / voxel_scale.z) * voxel_scale.z
	)
	rotation = Vector3.ZERO
	var voxel_coords = _to_voxel_cords(position)
	if voxel_coords in get_parent().voxel_resource.positions_dict:
		_voxel_coords = voxel_coords
	else:
		_voxel_coords = null

	update_configuration_warnings()


func _to_voxel_cords(cords: Vector3, voxel_scale: Vector3 = _voxel_scale):
	return Vector3i(
		round(cords.x/voxel_scale.x),
		round(cords.y/voxel_scale.y),
		round(cords.z/voxel_scale.z)
	)


func _update():
	var parent = get_parent()
	if parent is VoxelObject:
		_voxel_scale = get_parent().voxel_resource.vox_size
		_update_hint()
		_snap()
	else:
		update_configuration_warnings()


func _update_hint():
	var in_editor = Engine.is_editor_hint()
	if (in_editor and not show_postion_hint_in_editor) or (not in_editor and not show_postion_hint_during_runtime):
		return
	if not is_instance_valid(_hint_collision_node):
		_hint_collision_node = MeshInstance3D.new()
		add_child(_hint_collision_node)
	var hint_mesh = BoxMesh.new()
	hint_mesh.size = _voxel_scale + (_voxel_scale * .01) * 10
	_hint_collision_node.mesh = hint_mesh
	var hint_material = StandardMaterial3D.new()
	hint_material.transparency = 1
	hint_material.albedo_color = position_hint_color
	_hint_collision_node.material_override = hint_material

func _notification(what):
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if _postition_changed_override:
			_postition_changed_override = false
			return
		if _voxel_scale and _voxel_scale != Vector3.ZERO:
			_position_changed_timer = _POSITION_CHANGED_TIMER_SET
	
	elif what == NOTIFICATION_PARENTED:
		var parent = get_parent()
		if parent is VoxelObject:
			parent.connect("repopulated", repopulate)
			_update()
		update_configuration_warnings()
	
	elif what == NOTIFICATION_UNPARENTED:
		if get_parent() is VoxelObject:
			get_parent().disconnect("repopulated", repopulate)
		#_populated = false
		_voxel_scale = Vector2.ZERO
		_voxel_coords = null
		update_configuration_warnings()


func _get_configuration_warnings():
	var errors: Array[String] = []
	if not get_parent() is VoxelObject:
		_invalid = true
		return ["Must be a child of VoxelObject!"]
	elif not _voxel_coords:
		_invalid = false
		_snap()
		if not _voxel_coords:
			return ["Not located at a Voxel in parent VoxelObject!"]
	if errors.is_empty():
		_invalid = false
	else:
		_invalid = true
	return errors


func repopulate() -> void:
	_update()
