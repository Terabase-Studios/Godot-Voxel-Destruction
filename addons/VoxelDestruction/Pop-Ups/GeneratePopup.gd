@tool
extends Node

@export var mainLabel: Label
@export var DirectoryLabel: Label
@export var WarningLabel: Label
@export var generateButton: Button
@export var progressBar: ProgressBar
@export var animationPlayer: AnimationPlayer
@export var icon: Panel

var warning = 0
var finished = false
var VoxelNumber: int
var voxelGenerator: Node
var voxelCount: int
var objectName: String
var saveDirectory: String
var failsafe: bool

signal generated

func _ready() -> void:
	var start = true
	while start:
		var ETA = int((voxelCount-(VoxelNumber+1))/Engine.get_frames_per_second()/3)
		mainLabel.text = "Voxel Count: 
		("+str(voxelCount)+")
		ETA: "+str(ETA/60)+" min, "+str(ETA-(int(ETA/60)*60))+' sec'
		DirectoryLabel.text = "Directory: " + saveDirectory
		progressBar.max_value = voxelCount
		generateButton.pressed.connect(generate)
		await get_tree().process_frame
		start = false


func generate() -> void:
	voxelGenerator.call_deferred("StartGeneration")
	WarningLabel.visible = true
	generateButton.visible = false
	progressBar.visible = true
	icon.visible = true
	animationPlayer.play("loading")
	var FrameRate = [0, 0]
	while true:
		if FrameRate[1] > 100:
			FrameRate = [0, 0]
		FrameRate[0] += Engine.get_frames_per_second()
		FrameRate[1] += 1
		if Engine.get_frames_per_second() < 20:
			if warning != 1:
				warning = 1
				if failsafe:
					print('ERROR: Extreme Slow Speeds Detected
	---Emergency Kill---')
					self.queue_free()
		elif Engine.get_frames_per_second() < 60:
			if warning != 2:
				warning = 2
				print('ERROR: Slow Speeds Detected')
		else:
			warning = 0
		await get_tree().process_frame
		if voxelCount-(VoxelNumber+1) == 0:
			mainLabel.text = "Finishing things up"
			progressBar.value = VoxelNumber+1
			await generated
			progressBar.visible = false
			WarningLabel.visible = false
			icon.visible = false
			finished = true
			var closingTime = 5
			while true:
				mainLabel.text = "Voxel Saved
				Closing in: "+str(closingTime)
				closingTime -= 1
				await get_tree().create_timer(1).timeout
				if closingTime == 0:
					queue_free()
		else:
			var AvgFrameRate = FrameRate[0]/FrameRate[1]
			var ETA = int((voxelCount-(VoxelNumber+1))/AvgFrameRate/3)
			if VoxelNumber == 0:
				mainLabel.text = "Perparing Voxel Object
				ETA: "+str(ETA/60)+" min, "+str(ETA-(int(ETA/60)*60))+' sec'
				progressBar.value = VoxelNumber+1
				continue
			
			
			mainLabel.text = "Voxel Count: 
			("+str(VoxelNumber+1)+'/'+str(voxelCount)+")
			ETA: "+str(ETA/60)+" min, "+str(ETA-(int(ETA/60)*60))+' sec'
			progressBar.value = VoxelNumber+1


func _on_exit_button_up() -> void:
	if not finished:
		print("Voxel Generation Canceled")
	queue_free()


func _on_anim_play_animation_finished(anim_name: StringName) -> void:
	animationPlayer.play()

func done():
	generated.emit()
