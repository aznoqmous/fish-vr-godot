extends Node3D
@export var boat: Boat
@export var area_3d: Area3D

func _ready():
	boat.set_visible(false)
	boat.area_3d.monitoring = false
	area_3d.area_entered.connect(func(area):
		boat.set_visible(true)
		boat.area_3d.monitoring = true
	)
