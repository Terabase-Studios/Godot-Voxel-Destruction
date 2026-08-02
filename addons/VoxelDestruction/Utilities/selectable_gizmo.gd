@tool
extends EditorNode3DGizmoPlugin
class_name VDSelectableGizmo


func _get_gizmo_name():
	return "VDSelectable"


func _has_gizmo(node: Node3D) -> bool:
	return node is VoxelObject


func _init():
	create_material("main", Color.GRAY)
	#create_handle_material("handles")


func _redraw(gizmo: EditorNode3DGizmo):
	gizmo.clear()

	var voxel_object := gizmo.get_node_3d() as VoxelObject
	# TODO: Replace with voxel_resource.size to prevent recalculation
	var aabb := voxel_object.multimesh.get_aabb()

	gizmo.add_lines(
		_aabb_to_lines(aabb),
		get_material("main")
	)

	gizmo.add_collision_triangles(
		_aabb_to_triangle_mesh(aabb)
	)


func _aabb_to_triangle_mesh(aabb: AABB) -> TriangleMesh:
	var triangle_mesh := TriangleMesh.new()
	triangle_mesh.create_from_faces(_aabb_to_triangles(aabb))
	return triangle_mesh


func _aabb_to_triangles(aabb: AABB) -> PackedVector3Array:
	var p := aabb.position
	var s := aabb.size

	var v = [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(s.x, s.y, s.z),
		p + Vector3(0, s.y, s.z),
	]

	return PackedVector3Array([
		# Front
		v[0], v[1], v[2],
		v[0], v[2], v[3],

		# Back
		v[4], v[6], v[5],
		v[4], v[7], v[6],

		# Left
		v[0], v[3], v[7],
		v[0], v[7], v[4],

		# Right
		v[1], v[5], v[6],
		v[1], v[6], v[2],

		# Bottom
		v[0], v[4], v[5],
		v[0], v[5], v[1],

		# Top
		v[3], v[2], v[6],
		v[3], v[6], v[7],
	])



func _aabb_to_lines(aabb: AABB) -> PackedVector3Array:
	var p := aabb.position
	var s := aabb.size

	var v0 = p
	var v1 = p + Vector3(s.x, 0, 0)
	var v2 = p + Vector3(s.x, s.y, 0)
	var v3 = p + Vector3(0, s.y, 0)

	var v4 = p + Vector3(0, 0, s.z)
	var v5 = p + Vector3(s.x, 0, s.z)
	var v6 = p + Vector3(s.x, s.y, s.z)
	var v7 = p + Vector3(0, s.y, s.z)

	return PackedVector3Array([
		# Bottom
		v0, v1,
		v1, v2,
		v2, v3,
		v3, v0,

		# Top
		v4, v5,
		v5, v6,
		v6, v7,
		v7, v4,

		# Vertical
		v0, v4,
		v1, v5,
		v2, v6,
		v3, v7,
	])
