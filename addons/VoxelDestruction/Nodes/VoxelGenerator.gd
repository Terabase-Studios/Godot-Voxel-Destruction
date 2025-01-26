@tool
extends VoxelBase
class_name VoxelGenerator

@export var BUTTON_Generate_Voxel: String
@export_category("Base Configuration")
@export var SaveDirectory: String
@export var Failsafe = true
@export var MaterialOverride: Material
@export var VoxelHealth = 100
@export_category("Shield Options")
@export var Shielded = false
@export var MaxShield = 0
@export_category("Extra Features")
@export var Materials = []
@export var DefenceModifiers = []
@export var MultiplayerSync = false
@export_subgroup("DO NOT EDIT")
@export var ArmorIds := PackedInt32Array()

var GeneratePopup: Node
var resource: Resource
var SaveSceneDirectory: String
var VoxelObjectScene = null
var ShieldNode = null
var MultiplayerNode = null
var CollectionNode = null
var thread: Thread = Thread.new()  # Create a new thread
var updating = false

func _process(delta: float) -> void:
	if Materials.is_empty() or DefenceModifiers.is_empty():
		get_materials()

func get_materials() -> void:
	Materials = []
	DefenceModifiers = []
	ArmorIds = PackedInt32Array()
	for child in get_children():
		if child.mesh.surface_get_material(0) not in Materials:
			Materials.append(child.mesh.surface_get_material(0))
			DefenceModifiers.append(1.0)
		ArmorIds.append(Materials.find(child.mesh.surface_get_material(0)))

func _on_button_pressed(text: String) -> void:
	if text.to_upper() == "GENERATE VOXEL":
		if Materials.is_empty() or DefenceModifiers.is_empty():
			get_materials()

		print('--------------------')
		if DirAccess.open(SaveDirectory) == null:
			print_rich("[color=red]Invalid Directory[/color]")
			return

		SaveSceneDirectory = SaveDirectory

		if FileAccess.file_exists(SaveSceneDirectory + self.name + '.vox' + '/' + self.name + ".tscn"):
			var foundDirectory = false
			var addon = '(NEW)'
			while not foundDirectory:
				if FileAccess.file_exists(SaveSceneDirectory + str(addon) + self.name + '.vox' + '/' + self.name + ".tscn"):
					addon += '(NEW)'
				else:
					foundDirectory = true
					set_name.call_deferred(name + str(addon))

		if GeneratePopup != null:
			GeneratePopup.queue_free()
		GeneratePopup = preload("res://addons/VoxelDestruction/Pop-Ups/GeneratePopup.tscn").instantiate()
		GeneratePopup.name = self.name
		GeneratePopup.voxelGenerator = self
		GeneratePopup.voxelCount = self.get_child_count()
		GeneratePopup.objectName = self.name
		GeneratePopup.saveDirectory = SaveSceneDirectory + self.name + '.vox'
		GeneratePopup.failsafe = Failsafe
		VoxelDestructionGodot.new().add_popup(GeneratePopup)

func StartGeneration():
	thread = Thread.new()
	var callable = Callable(self, "_generate_thread").bind(SaveSceneDirectory + self.name + '.vox', get_children())
	var result = thread.start(callable)
	if result != OK:
		print("Failed to start thread.")

func _generate_thread(save_path: String, children: Array) -> void:
	generate(save_path, children)  # Perform thread-safe work
	call_deferred("_finalize_thread")

func _finalize_thread() -> void:
	if thread:
		thread.wait_to_finish()  # Safely finish thread
		thread = null  # Reset the thread


func generate(save_path: String, children) -> void:
	Thread.set_thread_safety_checks_enabled(false)
	var checkSize := func checkSize(node, minmax):
		if node.position.x < minmax[0]:
			minmax[0] = node.position.x
		if node.position.x > minmax[1]:
			minmax[1] = node.position.x
		if node.position.y < minmax[2]:
			minmax[2] = node.position.y
		if node.position.y > minmax[3]:
			minmax[3] = node.position.y
		if node.position.z < minmax[4]:
			minmax[4] = node.position.z
		if node.position.z > minmax[5]:
			minmax[5] = node.position.z
		return minmax

	print("Generating voxels...")
	if not updating:
		resource = VoxelResource.new()
	var DefenceOverrides = {}
	for i in Materials:
		DefenceOverrides[i] = DefenceModifiers[Materials.find(i)]

	VoxelObjectScene = VoxelObject.new()
	VoxelObjectScene.name = self.name
	CollectionNode = VoxelCollection.new()
	VoxelObjectScene.add_child(CollectionNode)
	CollectionNode.name = "Voxel Collection"
	CollectionNode.DefenceOverrides = DefenceOverrides

	#Preloads Variables that are Reused to Help with Speed
	var arrays = children[0].mesh.surface_get_arrays(0)
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var MeshBox = BoxMesh.new()
	MeshBox.surface_set_material(0, preload("res://addons/VoxelDestruction/Resources/Dark.tres"))
	var BoxShape = BoxShape3D.new()

	var VoxelNumber: float = -1
	var MinMax = [0, 0, 0, 0, 0, 0]

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material
	if MaterialOverride == null:
		material = StandardMaterial3D.new()
	else:
		material = MaterialOverride.duplicate()
	material.vertex_color_use_as_albedo = true
	material.set_transparency(4)
	st.set_material(material)

	for child in children:
		#AdjustSize
		var Vertices = PackedVector3Array()
		if child.position.x < MinMax[0]:
			MinMax[0] = child.position.x
		if child.position.x > MinMax[1]:
			MinMax[1] = child.position.x
		if child.position.y < MinMax[2]:
			MinMax[2] = child.position.y
		if child.position.y > MinMax[3]:
			MinMax[3] = child.position.y
		if child.position.z < MinMax[4]:
			MinMax[4] = child.position.z
		if child.position.z > MinMax[5]:
			MinMax[5] = child.position.z
		VoxelNumber += 1
		if not is_instance_valid(GeneratePopup):
			return
		GeneratePopup.VoxelNumber = VoxelNumber
		# Add Mesh to Main
		var mesh = BoxMesh.new()
		mesh.size = Vector3(.011, .011, .011)
		mesh.material = child.mesh.surface_get_material(0).duplicate()
		var transform3D = child.transform
		var Transform

		var Deviation = Vector3(float(randi_range(-10, 10)) / 10000, float(randi_range(-10, 10)) / 10000, float(randi_range(-10, 10)) / 10000)

		for i in range(indices.size()):
			var index = indices[i]
			var vertex = vertices[index]
			var normal = normals[index]

			# Transform and add vertex
			st.set_normal(transform3D.basis * normal)  # Transform the normal
			# Adjust for gamma to prevent object unsaturation
			var original_color = mesh.surface_get_material(0).albedo_color
			var corrected_color = Color(
				original_color.r ** 2.2,
				original_color.g ** 2.2,
				original_color.b ** 2.2,
				original_color.a
			)
			st.set_color(corrected_color)  # Apply per-vertex color
			Transform = transform3D * vertex
			# Helps differentiate what vertices to remove during voxel destruction
			Transform = Vector3(float(round(Transform.x)), float(round(Transform.y)), float(round(Transform.z))) + Deviation
			st.add_vertex(Transform)
			Vertices.append(Transform)

		# Create Voxel
		var VoxelNode = Voxel.new()
		VoxelNode.name = "Voxel " + str(VoxelNumber)
		VoxelNode.visible = false
		VoxelNode.position = Transform
		VoxelNode.MaxHealth = VoxelHealth
		VoxelNode.ArmorID = ArmorIds[VoxelNumber]
		VoxelNode.Verticies = Vertices

		mesh = child.duplicate()
		mesh.name = 'Mesh'
		mesh.mesh = MeshBox
		mesh.position = Vector3.ZERO
		mesh.scale = Vector3(1.02, 1.02, 1.02)
		mesh.set_cast_shadows_setting(0)
		VoxelNode.add_child(mesh)
		mesh.set_owner(VoxelNode)

		var StaticBody = StaticBody3D.new()
		StaticBody.name = "StaticBody"
		VoxelNode.add_child(StaticBody)
		StaticBody.set_owner(VoxelNode)

		var Collision = CollisionShape3D.new()
		Collision.name = "Collision"
		Collision.set_shape(BoxShape)
		StaticBody.add_child(Collision)
		Collision.set_owner(VoxelNode)

		if not updating:
			var voxelScene = PackedScene.new()
			voxelScene.pack(VoxelNode)
			resource.voxels.append(voxelScene)

			var childScene = PackedScene.new()
			childScene.pack(child.duplicate(true))
			resource.meshes.append(childScene)

	var Size = Vector3(1.2 * (abs(MinMax[0]) + abs(MinMax[1])), 1.2 * (abs(MinMax[2]) + abs(MinMax[3])), 1.2 * (abs(MinMax[4]) + abs(MinMax[5])))

	if Shielded:
		var ShieldNode = VoxelShield.new()
		ShieldNode.name = 'VoxelShield'
		ShieldNode.Multiplayer = MultiplayerSync
		ShieldNode.MaxShield = MaxShield
		ShieldNode.Size = Size
		VoxelObjectScene.add_child(ShieldNode)
		VoxelObjectScene.ShieldNode = ShieldNode
		ShieldNode.GenerateShield()

	if MultiplayerSync:
		var MultiplayerNode = VoxelMultiplayerSynchronizer.new()
		MultiplayerNode.name = 'VoxelMultiplayerSynchronizer'
		VoxelObjectScene.add_child(MultiplayerNode)

	var MainMesh = MeshInstance3D.new()
	MainMesh.name = "Voxel Mesh"
	MainMesh.mesh = st.commit()
	VoxelObjectScene.add_child(MainMesh)
	var Offset = Vector3(-.5, .5, .5)
	MainMesh.position = Offset

	var VoxelUpdaterScene = VoxelUpdater.new()
	VoxelUpdaterScene.name = "Voxel Updater"
	VoxelUpdaterScene.ChildCount = children.size()
	VoxelUpdaterScene.visible = false
	for variable in GetVariables():  # Assumes `get_var_list` returns a list of variable names
		VoxelUpdaterScene.set(variable, self.get(variable))
	VoxelObjectScene.add_child(VoxelUpdaterScene)

	self.call_deferred("save", VoxelObjectScene)


func save(NodeToSave):
	var dir = DirAccess.open(SaveSceneDirectory)
	dir.make_dir(NodeToSave.name+'.vox')
	DirAccess.make_dir_absolute(SaveSceneDirectory+NodeToSave.name+'.vox')  

	var directory = SaveSceneDirectory+'/'+NodeToSave.name+'.vox'
	var node = NodeToSave.duplicate()
	for child in node.get_children():
		child.set_owner(node)
		for child2 in child.get_children():
			child2.set_owner(node)
			for child3 in child2.get_children():
				child3.set_owner(node)
				for child4 in child3.get_children():
					child4.set_owner(node)
					for child5 in child4.get_children():
						child5.set_owner(node)
		name = name.replace('(NEW)', '')

	var save_scene  = PackedScene.new()
	save_scene.pack(node)

	var error = null
	if not updating:
		resource.take_over_path(directory+'/'+NodeToSave.name+'.tres')
		error = ResourceSaver.save(resource, directory+'/'+NodeToSave.name+'.tres')
		if error == OK:
			print_rich("[color=green]Voxel Resource saved successfully to: ", SaveSceneDirectory+NodeToSave.name+'.vox[/color]')
		else:
			print_rich("[color=red]Failed to save Resource. Error code: ", str(error)+"[/color]")

	error = ResourceSaver.save(save_scene, directory+'/'+NodeToSave.name+'.tscn', 64)
	if error == OK:
		print_rich("[color=green]Voxel Object saved successfully to: ", SaveSceneDirectory+NodeToSave.name+'.vox[/color]')
	else:
		print_rich("[color=red]Failed to save scene. Error code: ", str(error)+"[/color]")
	await get_tree().process_frame
	GeneratePopup.done()
	if updating:
		print_rich("[color=yellow]Please Reopen Scene[/color]")
	print('--------------------')

func GetVariables():
	return ["SaveDirectory", "Failsafe", "MaterialOverride", "VoxelHealth", "Shielded", "MaxShield", "Materials", "DefenceModifiers", "MultiplayerSync", "ArmorIds"]
