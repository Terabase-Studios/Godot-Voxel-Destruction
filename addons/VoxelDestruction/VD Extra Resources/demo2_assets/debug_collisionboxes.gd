extends Node3D

## Attach to any Node3D in your scene (e.g. as a child of Main).
## It will draw the bounding boxes of all VoxelObjects and VoxelDamagers each frame.
## Toggle with F1 at runtime.

@export var damager_color: Color = Color(1, 0.2, 0.2, 1)   # red
@export var object_color: Color = Color(0.2, 1, 0.2, 1)    # green
@export var visible_on_start: bool = true

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _material: StandardMaterial3D
var _enabled: bool = true


func _ready() -> void:
	_enabled = visible_on_start

	_immediate_mesh = ImmediateMesh.new()

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.flags_no_depth_test = true

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.top_level = true
	add_child(_mesh_instance)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_enabled = !_enabled
		_immediate_mesh.clear_surfaces()


func _process(_delta: float) -> void:
	_immediate_mesh.clear_surfaces()
	if not _enabled:
		return

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)

	var all_nodes = _get_all_nodes(get_tree().root)
	for node in all_nodes:
		if node.get_script() == null:
			continue
		var script_path: String = node.get_script().resource_path
		if "voxel_damager" in script_path:
			_draw_damager_box(node)
		elif "voxel_object" in script_path:
			_draw_object_aabb(node)

	_immediate_mesh.surface_end()


func _draw_damager_box(damager: Node3D) -> void:
	# Get the CollisionShape3D child
	for child in damager.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var size: Vector3 = child.shape.size
			var origin: Vector3 = damager.global_position
			_draw_wire_box(origin, size, damager_color)
			break


func _draw_object_aabb(obj: Node3D) -> void:
	# Use the MultiMeshInstance3D's AABB
	if obj is MultiMeshInstance3D and obj.multimesh:
		var aabb: AABB = obj.multimesh.get_aabb()
		# Transform AABB corners to global space
		var gt: Transform3D = obj.global_transform
		_draw_aabb_transformed(aabb, gt, object_color)


func _draw_wire_box(center: Vector3, size: Vector3, color: Color) -> void:
	var h: Vector3 = size * 0.5
	# 8 corners
	var corners = [
		center + Vector3(-h.x, -h.y, -h.z),
		center + Vector3( h.x, -h.y, -h.z),
		center + Vector3( h.x,  h.y, -h.z),
		center + Vector3(-h.x,  h.y, -h.z),
		center + Vector3(-h.x, -h.y,  h.z),
		center + Vector3( h.x, -h.y,  h.z),
		center + Vector3( h.x,  h.y,  h.z),
		center + Vector3(-h.x,  h.y,  h.z),
	]
	_draw_box_edges(corners, color)


func _draw_aabb_transformed(aabb: AABB, gt: Transform3D, color: Color) -> void:
	var lo: Vector3 = aabb.position
	var hi: Vector3 = aabb.end
	var corners = [
		gt * Vector3(lo.x, lo.y, lo.z),
		gt * Vector3(hi.x, lo.y, lo.z),
		gt * Vector3(hi.x, hi.y, lo.z),
		gt * Vector3(lo.x, hi.y, lo.z),
		gt * Vector3(lo.x, lo.y, hi.z),
		gt * Vector3(hi.x, lo.y, hi.z),
		gt * Vector3(hi.x, hi.y, hi.z),
		gt * Vector3(lo.x, hi.y, hi.z),
	]
	_draw_box_edges(corners, color)


func _draw_box_edges(c: Array, color: Color) -> void:
	# Bottom face
	_line(c[0], c[1], color); _line(c[1], c[2], color)
	_line(c[2], c[3], color); _line(c[3], c[0], color)
	# Top face
	_line(c[4], c[5], color); _line(c[5], c[6], color)
	_line(c[6], c[7], color); _line(c[7], c[4], color)
	# Vertical edges
	_line(c[0], c[4], color); _line(c[1], c[5], color)
	_line(c[2], c[6], color); _line(c[3], c[7], color)


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(a)
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(b)


func _get_all_nodes(node: Node) -> Array:
	var result = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_nodes(child))
	return result
