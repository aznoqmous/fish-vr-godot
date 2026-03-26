extends Node3D
class_name Boat

@onready var path_follow_3d: PathFollow3D = $Path3D/PathFollow3D
@onready var area_3d: Area3D = $Area3D
@export var speed := 3.0
@export var player : XROrigin3D

var navigate := false
var start_position : Vector3

func _ready():
	area_3d.area_entered.connect(func(area: Area3D):
		navigate = true
		area_3d.monitoring = false
		start_position = path_follow_3d.global_position - player.global_position
	)

func _process(delta):
	if navigate:
		path_follow_3d.progress += delta * speed
		player.global_position = path_follow_3d.global_position - start_position
		if path_follow_3d.progress_ratio >= 1: navigate = false
