@tool
extends VoxelBase
class_name VoxelObject

@export_storage var ShieldNode = null

@onready var resource = load(scene_file_path.replace('.tscn', '.tres'))
@onready var CollectionNode = $"Voxel Collection"
@onready var MeshNode = $"Voxel Mesh"

@export var Functional = true
@export var Shielded = false

var removedVerticies = PackedVector3Array()
var RegeningMesh = false
var VoxelCount = 0

var new_mesh = ArrayMesh.new()
var mutex: Mutex
var semaphore: Semaphore
var thread: Thread
var exit_thread := false

signal refreshed


func _ready() -> void:
	if ShieldNode == null:
		Shielded = false

	if not Engine.is_editor_hint():
		mutex = Mutex.new()
		semaphore = Semaphore.new()
		exit_thread = false

		# Create a new thread to handle the mesh update
		thread = Thread.new()
		thread.start(UpdateMesh)
		await CollectionNode.loaded
		VoxelCount = CollectionNode.get_child_count()
		UpdateCooldown()


func remove_voxel_part():
	RegeningMesh = true


func UpdateMesh():
	while true:
		semaphore.wait() # Wait until posted.
		
		mutex.lock()
		var should_exit = exit_thread # Protect with Mutex.
		mutex.unlock()
		
		if should_exit:
			break
		
		mutex.lock()
		var mdt = MeshDataTool.new()
		
		# Create MeshDataTool from the mesh
		mdt.create_from_surface(MeshNode.mesh.duplicate(), 0)
		
		var vertex_count = mdt.get_vertex_count()
		
		# Iterate over all vertices, modifying colors of matched points
		for i in range(vertex_count):
			var vertex = mdt.get_vertex(i)
			if vertex in removedVerticies:
				var color = mdt.get_vertex_color(i)
				mdt.set_vertex_color(i, Color(color.r, color.g, color.b, 0))  # Make transparent
		
		# Clear and recreate the mesh with updated vertex data
		new_mesh = ArrayMesh.new()
		mdt.commit_to_surface(new_mesh)
		MeshNode.set_deferred("mesh", new_mesh)
		print('hey')
		refreshed.emit.call_deferred()
		
		mutex.unlock()


func _exit_tree():
	if not Engine.is_editor_hint():
		# Set exit condition to true.
		mutex.lock()
		exit_thread = true # Protect with Mutex.
		mutex.unlock()

		# Unblock by posting.
		semaphore.post()

		# Wait until it exits.
		thread.wait_to_finish()

func UpdateCooldown():
	while true:
		if RegeningMesh:
			semaphore.post()
			RegeningMesh = false
			await refreshed
			print(refreshed)
		await get_tree().process_frame
