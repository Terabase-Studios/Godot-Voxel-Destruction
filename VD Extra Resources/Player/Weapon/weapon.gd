extends Node3D
var cooldown = 0

func _process(delta: float) -> void:
	cooldown -= delta
	cooldown = clamp(cooldown, 0, .3)
	if %Aim.is_colliding():
		look_at(%Aim.get_collision_point())
		self.rotation.y = clamp(self.rotation.y, -1, 1)

func use():
	if cooldown == 0:
		var bullet = load("res://Test World/Player/Weapon/Bullet.tscn").instantiate()
		self.add_child(bullet)
		bullet.name = 'Bullet'
		bullet.target = %Aim.get_collision_point()
		bullet.global_position = %"Fire Point".global_position
		cooldown = 3
		%AnimationPlayer.play('cooldown')
