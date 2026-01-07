@tool
extends MultiMeshInstance3D
class_name VoxelLOD

@export var lod_resource: VoxelResourceLOD
@export_range(1.1, 3, 0.1) var lod_factor = 1.5

@export_storage var _populated: bool = false

func repopulate():
	lod_resource = from_voxel_resource(get_parent().voxel_resource)
	populate_mesh()
	_populated = true
	update_configuration_warnings()


func from_voxel_resource(original: VoxelResource) -> VoxelResourceLOD:
	var lod = VoxelResourceLOD.new()

	lod.colors = original.colors.duplicate()
	lod.color_index = PackedByteArray() 
	lod.positions = PackedVector3Array()
	lod.vox_size = original.vox_size * lod_factor
	
	# Loop through original voxels and decimate
	for i in original.vox_count:
		var pos = original.positions[i]
		# Reduce accuracy by dividing by lod_factor and flooring
		var cell = Vector3(
			floor(pos.x / lod_factor),
			floor(pos.y / lod_factor),
			floor(pos.z / lod_factor)
		)

		var lod_pos = cell + Vector3(0.5, 0.5, 0.5)
		
		# Skip duplicates
		if lod.positions.has(lod_pos):
			continue
		
		lod.positions.append(lod_pos)
		lod.color_index.append(original.color_index[i])
	
	lod.vox_count = lod.positions.size()
	lod.voxel_reduction = 1.0 - (float(lod.vox_count)/float(original.vox_count))
	
	return lod

func populate_mesh():
	if lod_resource:
		# Buffers vars to prevent performence drop 
		# when finding vox color/position
		
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
		var undo_redo = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Populated Voxel Lod")
		undo_redo.add_do_property(self, &"multimesh", _multimesh)
		undo_redo.add_undo_property(self, &"multimesh", multimesh)
		undo_redo.commit_action()






func _notification(what):
	if what == NOTIFICATION_PARENTED:
		var parent = get_parent()
		if parent is VoxelObject:
			parent.connect("repopulated", repopulate)
		update_configuration_warnings()
	elif what == NOTIFICATION_UNPARENTED:
		if get_parent() is VoxelObject:
			get_parent().disconnect("repopulated", repopulate)
		_populated = false
		update_configuration_warnings()


func _get_configuration_warnings():
	var errors: Array[String] = []
	if not get_parent() is VoxelObject:
		return ["Must be a child of VoxelObject!"]
	elif not _populated:
		errors.append("Must be populated! Please press (Re)populate Mesh on parent VoxelObject")
	return errors
