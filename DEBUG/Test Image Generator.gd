extends Node3D

@export var voxel_resource: VoxelResource
@export var atlas: ImageTexture3D

func _ready():
	atlas = create_occupancy_texture(
		voxel_resource.size,
		voxel_resource.positions_dict,
		voxel_resource.color_index,
		voxel_resource.colors
	)
	if atlas:
		ResourceSaver.save(atlas, "res://DEBUG/occupancy_tex3d.res")
	else:
		push_error("Failed to create 3D occupancy texture.")

func create_occupancy_texture(
	size: Vector3i,
	positions_dict: Dictionary,
	color_induces: PackedByteArray,
	color_pallet: PackedColorArray
) -> ImageTexture3D:
	var slices: Array[Image] = []
	var format = Image.FORMAT_RGBA8

	for z in range(size.z):
		var image = Image.create(size.x, size.y, false, format)
		image.fill(Color(0, 0, 0, 0))  # Empty = red = 0

		for pos in positions_dict.keys():
			if typeof(pos) != TYPE_VECTOR3I or pos.z != z:
				continue

			image.set_pixel(pos.x, pos.y, Color(color_pallet[color_induces[positions_dict[pos]]], 1))

		slices.append(image)

	var texture_3d = ImageTexture3D.new()
	texture_3d.create(format, size.x, size.y, size.z, false, slices)
	return texture_3d
