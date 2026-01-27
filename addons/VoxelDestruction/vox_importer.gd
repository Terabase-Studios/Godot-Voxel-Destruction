# import_plugin.gd
@tool
extends EditorImportPlugin

const _REMOVED_VOXEL_MARKER := Vector3(-1, -7, -7)

enum Resource_type {
	DEFAULT = 0,
	COMPACT = 2
}

enum Presets { 
	SCALE,
	CHUNK_SIZE,
	RESOURCE_TYPE
}


func _get_preset_count():
	return Presets.size()


func _get_preset_name(preset_index):
	match preset_index:
		Presets.SCALE:
			return "Scale"
		Presets.CHUNK_SIZE:
			return "Chunk Size"
		Presets.RESOURCE_TYPE:
			return "Resource"
		_:
			return "Unknown"


func _get_import_options(path, preset_index):
	return [{
			   "name": "Scale",
			   "default_value": Vector3(.1, .1, .1),
			},
			{
			   "name": "Chunk_Size",
			   "default_value": Vector3(16, 16, 16),
			},
			{
			   "name": "Resource_type",
			   "default_value": Resource_type.DEFAULT,
			   "property_hint": PROPERTY_HINT_ENUM,
			   "hint_string": "Default,Compact"
			}]


func _get_option_visibility(path, option_name, options):
	return true


func _can_import_threaded() -> bool:
	return true


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
	return "tres"


func _get_resource_type():
	return "VoxelResource"


func _import(source_file, save_path, options, r_platform_variants, r_gen_files):
	# Create vars for resource
	var positions: PackedVector3Array
	var colors: PackedColorArray
	var materials: Dictionary
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
		push_error("Invalid .vox file format!: ", source_file)
		file.close()
		return []
	
	var version = file.get_32()
	
	var wait = 0
	# Read chunks
	while not file.eof_reached() and not wait == 20000:
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
		
		elif chunk_id == "MATL":
			var material_id := file.get_32()
			var property_count := file.get_32()

			var mat := Color(0, 0, 0, 0)

			for i in range(property_count):
				var key_len := file.get_32()
				var key := file.get_buffer(key_len).get_string_from_ascii()

				var val_len := file.get_32()
				var val := file.get_buffer(val_len).get_string_from_ascii()

				match key:
					"_metal": mat.r = float(val)
					"_rough": mat.g = float(val)
					"_emit":  mat.b = float(val)
					"_trans": mat.a = float(val)
					"_ior": pass
					"_d": pass
					"_type": pass

			# Store by material_id (1-based, like palette)
			materials[material_id] = mat

		else:
			# Skip unknown or unused chunks
			file.seek(file.get_position() + chunk_size)
			wait += 1
	
	file.close()
	
	# Validate Voxels
	if voxels.is_empty():
		push_error("No voxel data found.")
		return ERR_FILE_CORRUPT
	
	# Map materials to voxels
	for voxel in voxels:
		var id = voxel["color_index"]
		if materials.has(id):
			voxel["material"] = materials[id]
		else:
			voxel["material"] = Color(0, 0, 0, 0)
	
	# Find the origin
	var origin = size/Vector3(round(2), round(2), round(2))
	
	# Create VoxelResource, some variables will be set later.
	var voxel_resource = VoxelResource.new()
	if options.Resource_type == 1:
		voxel_resource = CompactVoxelResource.new()
	else:
		voxel_resource = VoxelResource.new()
	voxel_resource.buffer_all()
	voxel_resource.vox_count = voxels.size()
	voxel_resource.vox_size = scale
	voxel_resource.origin = origin
	voxel_resource.size = size
	voxel_resource.health.resize(positions.size())
	voxel_resource.health.fill(100)
	
	# Create Object/Add colors/Update Positions
	var start_voxel = voxels[0]
	if not start_voxel.has("color") or not start_voxel["color"] or not start_voxel["color"] is Color: 
		push_warning("Color data missing or invalid: ", source_file)

	if start_voxel["position"] == null or not (start_voxel["position"] is Vector3 or start_voxel["position"] is Vector3i): 
		push_warning("Positions data missing or invalid; Import Failed: ", source_file)
		return
	var index = 0
	for voxel in voxels:
		var color = voxel.get("color", Color.PURPLE)
		if color not in voxel_resource.colors:
			voxel_resource.colors.append(color)
			voxel_resource.materials[color] = voxel["material"]
		voxel_resource.color_index.append(voxel_resource.colors.find(color))
		
		var position = voxel["position"]
		var adjusted_position = Vector3i(position.x, position.z, position.y)
		voxel_resource.positions.append(adjusted_position)
		voxel_resource.positions_dict[adjusted_position] = index
		index += 1
	
	# Modify object/add resource/finish Voxel Resource
	voxel_resource.debuffer_all()
	
	var chunk_size
	if options.Chunk_Size:
		chunk_size = options.Chunk_Size
	else:
		chunk_size = Vector3(16, 16, 16)
	
	# Sort axes
	var vox_chunk_indices: PackedVector3Array
	var chunks: Dictionary[Vector3, PackedVector3Array]
	
	# Create voxel dictionary
	for voxel: Vector3i in voxel_resource.positions:
		var chunk = Vector3(int(voxel.x/chunk_size.x), int(voxel.y/chunk_size.y), int(voxel.z/chunk_size.z))
		vox_chunk_indices.append(chunk)
		if not chunks.has(chunk):
			chunks[chunk] = PackedVector3Array()
		chunks[chunk].append(voxel)
	
	# Create collision
	var starting_shapes = Array()
	for chunk in chunks:
		starting_shapes.append_array(create_shapes(create_boxes(chunks[chunk]), scale, chunk))
	
	# Set collision VoxelResource vars
	voxel_resource.vox_chunk_indices = vox_chunk_indices
	voxel_resource.chunks = chunks
	voxel_resource.starting_shapes = starting_shapes
	
	# Get visible voxels
	# Store voxels in a dictionary with collision handling
	var voxel_map: Dictionary = {}
	var visible_voxels = PackedVector3Array()
	var offsets = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
				   Vector3i(0, 1, 0), Vector3i(0, -1, 0),
				   Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

	# Populate hash map
	for vox: Vector3i in voxel_resource.positions:
		var hash = hash_voxel(vox)
		if hash in voxel_map:
			voxel_map[hash].append(vox)  # Handle collisions by storing multiple voxels at the same hash
		else:
			voxel_map[hash] = [vox]
	
	# Find visible voxels
	for vox: Vector3i in voxel_resource.positions:
		for offset in offsets:
			var neighbor_vox: Vector3i = vox + offset
			var hash = hash_voxel(neighbor_vox)
			
			# Check if the hash exists AND verify actual position match
			if hash not in voxel_map or neighbor_vox not in voxel_map[hash]:
				visible_voxels.append(vox)
				break  # No need to check other directions
	
	voxel_resource.buffer("visible_voxels")
	voxel_resource.visible_voxels = visible_voxels
	
	# Set data size if compressed voxel obj:
	if options.Resource_type == 1:
		var initial_data_size: float = 0
		var compressed_data_size: float = 0
		for bytes in voxel_resource._property_size.values():
			initial_data_size += bytes
		for property in voxel_resource._data:
			var bytes = voxel_resource._data[property].size()
			compressed_data_size += bytes
		voxel_resource.compression = (1-(compressed_data_size/initial_data_size)) * 100
	
	voxel_resource.debuffer_all()
	
	var err = ResourceSaver.save(voxel_resource, "%s.%s" % [save_path, _get_save_extension()])
	if err != OK:
		print(ERROR_DESCRIPTIONS[err])
	return err


func hash_voxel(v: Vector3i) -> int:
	return ((v.x * 73856093) ^ (v.y * 19349663) ^ (v.z * 83492791)) % 1000003


func create_boxes(chunk: PackedVector3Array) -> Array:
	var visited: Dictionary[Vector3, bool]
	var boxes = []

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
					if not chunk.has(check_pos) or visited.get(check_pos, false):
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

		boxes.append({"min": box_min, "max": box_max})

	return boxes


func create_shapes(boxes: Array, voxel_size: Vector3, chunk) -> Array:
	var shapes = []
	for box in boxes:
		var min_pos = box["min"]
		var max_pos = box["max"]
		
		var center = (min_pos + max_pos) * 0.5 * voxel_size
		var size = ((max_pos - min_pos) + Vector3.ONE) * voxel_size
		shapes.append({"extents": size * 0.5, "position": center, "chunk": chunk})
	
	return shapes



const ERROR_DESCRIPTIONS = {
	0: "OK: No error, operation was successful.",
	1: "FAILED: Generic error, the operation failed but no specific reason is given.",
	2: "ERR_UNAVAILABLE: The requested resource or operation is unavailable.",
	3: "ERR_UNCONFIGURED: The object is not properly configured for use.",
	4: "ERR_UNAUTHORIZED: Operation not allowed due to permission restrictions.",
	5: "ERR_PARAMETER_RANGE_ERROR: A given parameter is out of the expected range.",
	6: "ERR_OUT_OF_MEMORY: Memory allocation failed due to lack of memory.",
	7: "ERR_FILE_NOT_FOUND: The specified file does not exist.",
	8: "ERR_FILE_BAD_DRIVE: The specified drive is invalid or does not exist.",
	9: "ERR_FILE_BAD_PATH: The provided file path is malformed.",
	10: "ERR_FILE_NO_PERMISSION: No permission to read/write the file.",
	11: "ERR_FILE_ALREADY_IN_USE: The file is locked or being used by another process.",
	12: "ERR_FILE_CANT_OPEN: The file could not be opened (cause unknown).",
	13: "ERR_FILE_CANT_WRITE: The file cannot be written to.",
	14: "ERR_FILE_CANT_READ: The file cannot be read.",
	15: "ERR_FILE_UNRECOGNIZED: The file format is not recognized.",
	16: "ERR_FILE_CORRUPT: The file is corrupt or unreadable.",
	17: "ERR_FILE_MISSING_DEPENDENCIES: The file requires missing dependencies.",
	18: "ERR_FILE_EOF: End of file reached unexpectedly.",
	19: "ERR_CANT_OPEN: A resource or connection cannot be opened.",
	20: "ERR_CANT_CREATE: A resource or file cannot be created.",
	21: "ERR_QUERY_FAILED: A query operation failed.",
	22: "ERR_ALREADY_IN_USE: The resource or operation is already in use.",
	23: "ERR_LOCKED: The resource is locked and cannot be modified.",
	24: "ERR_TIMEOUT: The operation timed out.",
	25: "ERR_CANT_CONNECT: Failed to establish a connection.",
	26: "ERR_CANT_RESOLVE: Unable to resolve a network address.",
	27: "ERR_CONNECTION_ERROR: Generic connection failure.",
	28: "ERR_CANT_ACQUIRE_RESOURCE: Cannot acquire the required resource.",
	29: "ERR_CANT_FORK: Forking a process failed (not commonly used in Godot).",
	30: "ERR_INVALID_DATA: Invalid data format or structure.",
	31: "ERR_INVALID_PARAMETER: An invalid parameter was passed to a function.",
	32: "ERR_ALREADY_EXISTS: The resource already exists and cannot be duplicated.",
	33: "ERR_DOES_NOT_EXIST: The requested resource does not exist.",
	34: "ERR_DATABASE_CANT_READ: Unable to read from the database.",
	35: "ERR_DATABASE_CANT_WRITE: Unable to write to the database.",
	36: "ERR_COMPILATION_FAILED: Compilation error in script or shader.",
	37: "ERR_METHOD_NOT_FOUND: The requested method does not exist.",
	38: "ERR_LINK_FAILED: Linking process failed.",
	39: "ERR_SCRIPT_FAILED: The script execution encountered an error.",
	40: "ERR_CYCLIC_LINK: A cyclic link dependency was detected.",
	41: "ERR_INVALID_DECLARATION: Invalid declaration syntax in script.",
	42: "ERR_DUPLICATE_SYMBOL: A duplicate symbol was found in code.",
	43: "ERR_PARSE_ERROR: Parsing error in script or file.",
	44: "ERR_BUSY: The requested resource is busy.",
	45: "ERR_SKIP: The operation was intentionally skipped.",
	46: "ERR_HELP: Help command error (rarely used).",
	47: "ERR_BUG: Internal bug encountered.",
	48: "ERR_PRINTER_ON_FIRE: Printer is on fire! (joke error, rarely used)."
}
