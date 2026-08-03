@tool
extends RefCounted
class_name VoxelObjectUtilities


static func populate(vo: VoxelObject) -> void:
	if vo._populating:
		return
	vo._populating = true
	if vo.voxel_resource:
		EditorInterface.mark_scene_as_unsaved()

		var popup = await VoxelDestructionGodot.create_process("Populating Voxel Mesh", "Preparing")

		# Buffers vars to prevent performence drop
		# when finding vox color/position
		vo.voxel_resource.buffer("positions")
		vo.voxel_resource.buffer("color_index")
		vo.voxel_resource.buffer("colors")
		vo.voxel_resource.buffer("visible_voxels")
		vo.multimesh = null
		# Create multimesh
		var _multimesh = VoxelMultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh.use_colors = true
		if vo.use_material:
			_multimesh.use_custom_data = true
		_multimesh.instance_count = vo.voxel_resource.vox_count
		_multimesh.create_indexes()
		_multimesh.visible_instance_count = 0
		# Create mesh
		var mesh = BoxMesh.new()
		mesh.material = preload("res://addons/VoxelDestruction/Resources/voxel_material.tres")
		mesh.size = vo.voxel_resource.vox_size
		_multimesh.mesh = mesh

		var new_color_pallet := PackedColorArray()
		var new_colors := PackedByteArray()

		var dithering_enabled := vo.dark_dithering != 0 or vo.light_dithering != 0
		var random: RandomNumberGenerator
		var dark_table: Array[float] = []
		var light_table: Array[float] = []
		if dithering_enabled:
			random = RandomNumberGenerator.new()
			random.set_seed(vo.dithering_seed)
			dark_table = [
				-vo.dark_dithering,
				-vo.dark_dithering * 0.66,
				-vo.dark_dithering * 0.33
			]
			light_table = [
				vo.light_dithering * 0.33,
				vo.light_dithering * 0.66,
				vo.light_dithering
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

			var vox_color: Color = vo._get_vox_color(i)
			var final_color := vox_color

			if dithering_enabled:
				# Pick one of the predefined brightness variations
				var variation := 0.0
				if vo.dark_dithering == 0:
					variation = light_table[random.randi() % light_table.size()]
				elif vo.light_dithering == 0:
					variation = dark_table[random.randi() % dark_table.size()]
				elif random.randf() > vo.dithering_bias:
					variation = dark_table[random.randi() % dark_table.size()]
				else:
					variation = light_table[random.randi() % light_table.size()]
				if variation < 0:
					final_color = vox_color.darkened(-variation)
				else:
					final_color = vox_color.lightened(variation)

			var vox_pos = vo.voxel_resource.positions[i]
			if vox_pos in vo.voxel_resource.visible_voxels:
				_multimesh.set_instance_visibility(i, true)
			_multimesh.voxel_set_instance_transform(
				i, Transform3D(Basis(), vox_pos * vo.voxel_resource.vox_size)
			)
			if vo.use_material and vo.voxel_resource.materials.has(vox_color):
				_multimesh.voxel_set_instance_custom_data(
					i, vo.voxel_resource.materials[vox_color]
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
		new_voxel_state.version = vo._VOXELSTATE_VERSION
		new_voxel_state.colors = new_color_pallet
		new_voxel_state.color_index = new_colors
		new_voxel_state.unique_voxel_resource = vo.voxel_resource.duplicate(true)
		vo._voxel_state = vo._cache_resource(new_voxel_state)
		#var undo_redo = EditorInterface.get_editor_undo_redo()
		#undo_redo.create_action("Populated Voxel Object")
		#undo_redo.add_do_property(self, &"multimesh", _multimesh)
		#undo_redo.add_undo_property(self, &"multimesh", multimesh)
		#undo_redo.commit_action()
		vo.multimesh = vo._cache_resource(_multimesh)

		popup.sub_text = "Giving Addons their turn!"
		await popup.redraw()
		if vo.lod_addon:
			vo.lod_addon._parent = vo
			vo.lod_addon.repopulate()

		vo.repopulated.emit()
		popup.queue_free()

		# Extra safeguard for save mid populate
		EditorInterface.mark_scene_as_unsaved()
	vo._populating = false


static func create_boxes(chunk: PackedVector3Array) -> Array:
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

		boxes.append({"min": box_min, "max": box_max})

	return boxes


static func create_shapes(boxes: Array, voxel_size: Vector3, chunk) -> Array:
	var shapes = []
	for box in boxes:
		var min_pos = box["min"]
		var max_pos = box["max"]
		
		var center = (min_pos + max_pos) * 0.5 * voxel_size
		var size = ((max_pos - min_pos) + Vector3.ONE) * voxel_size
		shapes.append({"extents": size * 0.5, "position": center, "chunk": chunk})
	
	return shapes
