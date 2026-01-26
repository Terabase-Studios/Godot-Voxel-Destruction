extends MultiMesh
class_name VoxelMultiMesh

## Allows easy editing of instance visibility. [br]
## This class should always be refrenced as a .tres file and never inlined in a scene! [br]
## Massive performance problems can occur. [br]
## [br]
## Moves instances indices and adjusts visible instances.

## Keeps track of moved indices
@export_storage var induces: Dictionary[int, int]
## Inverse to quickly edit induces
@export_storage var inversed_induces: Dictionary[int, int]

## Call this to create indices to correctly modify visibility. [br]
## Call *after* instances have been set. This will clear any existing indices.
func create_indexes() -> void:
	induces.clear()
	inversed_induces.clear()
	for instance in range(instance_count):
		induces[instance] = instance
		inversed_induces[instance] = instance
	visible_instance_count = instance_count

## Hides or shows an instance
func set_instance_visibility(instance: int, visible: bool) -> void:
	var adjusted_instance = induces[instance]
	var is_visible = adjusted_instance < visible_instance_count

	if visible and not is_visible:
		# Make instance visible
		visible_instance_count += 1
		if adjusted_instance != visible_instance_count - 1:
			swap(instance, adjusted_instance, inversed_induces[visible_instance_count - 1], visible_instance_count - 1)

	elif not visible and is_visible:
		# Hide instance
		visible_instance_count -= 1
		if adjusted_instance != visible_instance_count:
			swap(instance, adjusted_instance, inversed_induces[visible_instance_count], visible_instance_count)


## Changes the indices in the MultiMesh
func swap(instance_a_key: int, instance_a: int, instance_b_key: int, instance_b: int) -> void:
	# Swap transforms
	var transform_a = get_instance_transform(instance_a)
	var transform_b = get_instance_transform(instance_b)
	set_instance_transform(instance_a, transform_b)
	set_instance_transform(instance_b, transform_a)

	# Swap colors if enabled
	if use_colors:
		var color_a = get_instance_color(instance_a)
		var color_b = get_instance_color(instance_b)
		set_instance_color(instance_a, color_b)
		set_instance_color(instance_b, color_a)

	# Swap custom data if enabled
	if use_custom_data:
		var custom_a = get_instance_custom_data(instance_a)
		var custom_b = get_instance_custom_data(instance_b)
		set_instance_custom_data(instance_a, custom_b)
		set_instance_custom_data(instance_b, custom_a)

	# Swap indices in dictionaries
	induces[instance_a_key] = instance_b
	induces[instance_b_key] = instance_a
	inversed_induces[instance_b] = instance_a_key
	inversed_induces[instance_a] = instance_b_key


## See [member MultiMesh.set_instance_color]
func voxel_set_instance_color(instance: int, color: Color) -> void:
	set_instance_color(induces[instance], color)


## See [member MultiMesh.set_instance_custom_data]
func voxel_set_instance_custom_data(instance: int, custom_data: Color) -> void:
	set_instance_custom_data(induces[instance], custom_data)


## Use this instead of [member MultiMesh.set_instance_transform]
func voxel_set_instance_transform(instance: int, transform: Transform3D) -> void:
	set_instance_transform(induces[instance], transform)
