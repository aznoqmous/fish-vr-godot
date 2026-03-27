extends Node3D
@export var boat: Boat
@export var area_3d: Area3D
@export var explosion_particles: GPUParticles3D
@export var disabled_object: Node3D

func _ready():
	boat.set_visible(false)
	boat.area_3d.monitoring = false
	area_3d.area_entered.connect(func(area):
		if disabled_object: disabled_object.set_visible(false)
		if boat:
			boat.set_visible(true)
			boat.area_3d.monitoring = true
		if explosion_particles: explosion_particles.emitting = true
	)
