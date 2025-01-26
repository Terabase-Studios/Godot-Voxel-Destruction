@tool
extends VoxelComponent
class_name VoxelShield

@export_storage var MaxShield: float
@export_storage var Size: Vector3
@export_storage var Multiplayer: bool

@export var Shield: float
@export var Powered = true

var material = preload("res://addons/VoxelDestruction/Resources/ShieldMaterial.tres")
var ShieldGradient = preload("res://addons/VoxelDestruction/Resources/ShieldGradient.tres")
var ShieldGradientGlow = preload("res://addons/VoxelDestruction/Resources/ShieldGradientGlow.tres")

func _ready() -> void:
	Shield = MaxShield

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var mesh: MeshInstance3D = get_child(0)
	var object: StaticBody3D = get_child(1)
	var collision: CollisionShape3D = get_child(1).get_child(0)
	mesh.transparency = .99
	if get_parent().Functional:
		if Shield == 0 or Powered == false:
			get_parent().Shielded = false
			visible = false
			collision.disabled = true
		else:
			get_parent().Shielded = true
			visible = true
			collision.disabled = false
			if mesh.get_active_material(0) != null:
				var material = mesh.get_active_material(0).duplicate()
				var color = ShieldGradient.sample(1-(Shield/MaxShield))
				material.albedo_color = color
				color = ShieldGradient.sample(1-(Shield/MaxShield))
				material.emission = color
				material.emission_energy_multiplier = 16*Shield/MaxShield
				mesh.material_override = material

# Called when the node enters the scene tree for the first time.
func GenerateShield() -> void:
	var mesh = MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = BoxMesh.new()
	mesh.mesh.material = material
	mesh.scale = Size+Vector3(1, 1, 1)
	mesh.transparency = .95
	add_child(mesh)

	var object = StaticBody3D.new()
	object.name = "StaticBody"
	add_child(object)

	var collision = CollisionShape3D.new()
	collision.name = "Collision"
	collision.set_shape(BoxShape3D.new())
	collision.shape.size = Size+Vector3(1.01, 1.01, 1.01)
	object.add_child(collision)

func damage(damage):
	Shield = clamp(Shield-damage, 0, MaxShield)
