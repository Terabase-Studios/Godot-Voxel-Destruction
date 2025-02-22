# import_plugin.gd
@tool
extends EditorImportPlugin


enum Presets { 
	SCALE
}


func _get_preset_count():
	return Presets.size()



func _get_preset_name(preset_index):
	match preset_index:
		Presets.SCALE:
			return "Scale"
		_:
			return "Unknown"


func _get_import_options(path, preset_index):
	match preset_index:
		Presets.SCALE:
			return [{
					   "name": "Scale",
					   "default_value": Vector3(.1, .1, .1)
					}]


func _get_option_visibility(path, option_name, options):
	return true


func _can_import_threaded() -> bool:
	return false


func _get_importer_name():
	return "vox_object.voxel_destruction"


func _get_visible_name():
	return "Voxel Object"


func _get_priority():
	return 1


func _get_import_order():
	return 0


func _get_recognized_extensions():
	return ["vox"]


func _get_save_extension():
	return "tscn"


func _get_resource_type():
	return "PackedScene"


func _import(source_file, save_path, options, r_platform_variants, r_gen_files):
	# Create vars for resource
	var positions: PackedVector3Array
	var colors: PackedColorArray
	var size: Vector3
	
	# Load settings
	var scale
	if options.Scale:
		scale = options.Scale
	else:
		scale = Vector3(.1, .1, .1)
	
	var file = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	
	var voxels = []
	
	# Read the file header
	var magic = file.get_buffer(4).get_string_from_ascii()
	if magic != "VOX ":
		print("Invalid .vox file format!")
		file.close()
		return []
	
	var version = file.get_32()
	
	var wait = 0
	# Read chunks
	while not file.eof_reached() and not wait == 20:
		var chunk_id = file.get_buffer(4).get_string_from_ascii()
		var chunk_size = file.get_32()
		var child_chunk_size = file.get_32()
		
		if chunk_id == "SIZE":
			# SIZE chunk (contains model dimensions)
			var size_x = file.get_32()
			var size_y = file.get_32()
			var size_z = file.get_32()
			size = Vector3(size_x, size_z, size_y)
		
		elif chunk_id == "XYZI":
			# XYZI chunk (contains voxel data)
			var num_voxels = file.get_32()
			for i in range(num_voxels):
				var x = file.get_8()
				var y = file.get_8()
				var z = file.get_8()
				var color_index = file.get_8()
				voxels.append({"position": Vector3(x, y, z), "color_index": color_index})
				positions.append(Vector3(x, y, z))
		
		elif chunk_id == "RGBA":
			# RGBA chunk (contains palette data)
			var palette = []
			for i in range(256):
				var r = file.get_8()
				var g = file.get_8()
				var b = file.get_8()
				var a = file.get_8()
				palette.append(Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0))
			for voxel in voxels:
				voxel["color"] = palette[voxel["color_index"] - 1]
				colors.append(palette[voxel["color_index"] - 1])
		
		else:
			# Skip unknown or unused chunks
			file.seek(file.get_position() + chunk_size)
			wait += 1
	
	file.close()
	
	# Create resources
	var voxel_resource = VoxelResource.new()
	var damage_resource = DamageResource.new()
	var health: PackedInt32Array
	health.resize(positions.size())
	health.fill(100)
	var origin: Vector3 = size/Vector3(round(2), round(2), round(2))
	voxel_resource.positions = PackedVector3Array()
	voxel_resource.positions_dict = {}
	voxel_resource.colors = PackedColorArray(colors)
	voxel_resource.origin = origin
	voxel_resource.size = size
	damage_resource.health = PackedInt32Array(health)
	
	# Create Object/Add colors
	var voxel_object = VoxelObject.new()
	var color_list = PackedColorArray()
	var index = 0
	for voxel in voxels:
		var color = voxel["color"]
		if color not in color_list:
			color_list.append(color)
		
		var position = voxel["position"]
		# Adjust position for godot
		var adjusted_position = Vector3i(position.x, position.z, position.y)
		voxel_resource.positions.append(adjusted_position)
		voxel_resource.positions_dict[adjusted_position] = index
		index += 1
	
	# Validate Voxels
	if voxels.is_empty():
		print_rich("[COLOR=red]Error: No voxel data found. Aborting save.[/COLOR]")
		return ERR_FILE_CORRUPT
	
	# Modify object/add resource
	damage_resource.positions = voxel_resource.positions.duplicate()
	damage_resource.positions_dict = voxel_resource.positions_dict.duplicate()
	voxel_object.voxel_resource = voxel_resource
	voxel_object.damage_resource = damage_resource
	voxel_object.size = scale
	voxel_object.position = origin * scale * Vector3(-1, 0, -1)
	voxel_object.name = source_file.split('/')[source_file.split('/').size()-1].replace(".vox", "")
	
	# Populate mesh
	voxel_object.multimesh = MultiMesh.new()
	voxel_object.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	voxel_object.multimesh.use_colors = true
	voxel_object.multimesh.instance_count = voxel_resource.positions.size()
	var mesh = BoxMesh.new()
	mesh.material = preload("res://addons/VoxelDestruction/Resources/voxel_material.tres")
	mesh.size = scale
	voxel_object.multimesh.mesh = mesh
	# Set the transform of the instances.
	for i in voxel_object.multimesh.instance_count:
		voxel_object.multimesh.set_instance_transform(i, Transform3D(Basis(), voxel_resource.positions[i]*scale))
		voxel_object.multimesh.set_instance_color(i, voxel_resource.colors[i])
	
	# Save Scene
	var voxel_scene = PackedScene.new()
	voxel_scene.pack(voxel_object)
	
	var err = ResourceSaver.save(voxel_scene, "%s.%s" % [save_path, _get_save_extension()])
	if err != OK:
		print(err)
	return err
	
