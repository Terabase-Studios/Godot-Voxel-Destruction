extends Node3D

@export var voxel_resource: VoxelResourceBase
@export var atlas: ImageTexture3D


func _ready():
	atlas = voxel_dict_to_texture_slices(
		voxel_resource.size,
		voxel_resource.positions_dict,
		voxel_resource.colors,
		voxel_resource.color_index,
		true  # Set to false if only occupancy data is needed
	)
	if atlas:
		ResourceSaver.save(atlas, "res://test")
		#shader_material.set_shader_parameter("voxel_texture", tex3d)
	else:
		push_error("Failed to create 3D texture.")


func voxel_dict_to_texture_slices(
	size: Vector3i,
	positions_dict: Dictionary,
	colors: PackedColorArray = PackedColorArray(),
	color_index: PackedByteArray = PackedByteArray(),
	store_color: bool = true
) -> ImageTexture3D:
	var slices: Array[Image] = []

	# Determine the image format based on whether color data should be stored
	var format = Image.FORMAT_RGBA8 if store_color else Image.FORMAT_R8

	# Iterate over each slice along the Y-axis
	for y in range(size.y):
		# Create a new Image for the current slice
		var image = Image.create(size.x, size.z, false, format)

		# Iterate over each voxel position in the dictionary
		for pos in positions_dict.keys():
			if typeof(pos) != TYPE_VECTOR3I:
				continue

			# Check if the voxel is in the current slice
			if pos.y == y:
				var index = positions_dict[pos]
				var color = Color(1.0, 1.0, 1.0, 1.0)  # Default to white

				if store_color:
					if index < color_index.size():
						var color_id = color_index[index]
						if color_id < colors.size():
							color = colors[color_id]
				else:
					color = Color(1.0, 0.0, 0.0, 1.0)  # Red channel indicates occupancy

				# Set the pixel color at the corresponding position in the slice
				image.set_pixel(pos.x, pos.z, color)
		slices.append(image)
	# Create a texture3d
	var image_3d = ImageTexture3D.new()
	image_3d.create(format, size.x, size.z, size.y, false, slices)
	return image_3d
