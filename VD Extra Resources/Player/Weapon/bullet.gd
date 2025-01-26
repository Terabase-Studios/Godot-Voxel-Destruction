extends Node3D

@onready var mesh = $Body
var velocity = 5
var brange = 30
var distTraveled = 0
var target
var lastPostition
var hit = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not hit:
		lastPostition = position
		if position != target:
			look_at(target)
		global_transform.origin = global_transform.origin.move_toward(target, velocity * delta)
		distTraveled += velocity * delta
		if distTraveled > brange:
			hit = true
			$Body.visible = false
			$GPUParticles3D.emitting = true
			$Body.queue_free()
			await $GPUParticles3D.finished
			self.queue_free()



func _on_bullet_collision_body_entered(body: Node3D) -> void:
	if is_instance_valid(self) and is_instance_valid(mesh):
		if not body.get_parent() is CharacterBody3D:
			hit = true
			mesh.visible = false
			$VoxelDamager.hit()
			$Body.visible = false
			$Body.queue_free()
			$GPUParticles3D.emitting = true
			$AnimationPlayer.play("fire")
			%Blast.visible = true
			await $GPUParticles3D.finished
			self.queue_free()
