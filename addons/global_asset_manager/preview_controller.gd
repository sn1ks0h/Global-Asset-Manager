@tool
class_name PreviewController
extends RefCounted
## Handles 2D and 3D preview manipulations (orbit, pan, zoom).

var pivot: Node3D
var camera: Camera3D
var texture_rect: TextureRect

var _is_orbiting: bool = false
var _is_panning_3d: bool = false
var _is_panning_2d: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

var _yaw: float = 0.0
var _pitch: float = 0.0
var _initial_cam_transform: Transform3D

func reset_views() -> void:
	_yaw = 0.0
	_pitch = 0.0
	if is_instance_valid(pivot):
		pivot.transform.basis = Basis.IDENTITY
		pivot.position = Vector3.ZERO
	if is_instance_valid(camera):
		if _initial_cam_transform == Transform3D():
			_initial_cam_transform = camera.transform
		camera.transform = _initial_cam_transform

	if is_instance_valid(texture_rect):
		texture_rect.scale = Vector2.ONE
		texture_rect.position = Vector2.ZERO

func handle_3d_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_orbiting = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning_3d = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			# Zoom in along the camera's actual line of sight
			camera.global_position -= camera.global_transform.basis.z * 0.5
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			# Zoom out along the camera's actual line of sight
			camera.global_position += camera.global_transform.basis.z * 0.5

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var delta: Vector2 = motion.position - _last_mouse_pos
		_last_mouse_pos = motion.position

		if _is_orbiting:
			_yaw += delta.x * 0.01
			_pitch += delta.y * 0.01
			_pitch = clampf(_pitch, -PI / 2.5, PI / 2.5)

			pivot.transform.basis = Basis.IDENTITY

			# Rotate relative to the camera's orientation so screen-space movement always feels perfectly vertical/horizontal
			var cam_up := camera.global_transform.basis.y.normalized()
			var cam_right := camera.global_transform.basis.x.normalized()

			pivot.global_rotate(cam_up, _yaw)
			pivot.global_rotate(cam_right, _pitch)

		elif _is_panning_3d:
			var right := camera.global_transform.basis.x
			var up := camera.global_transform.basis.y

			# Calculate distance from camera to pivot to dynamically adjust pan speed
			var dist := camera.global_position.distance_to(pivot.global_position)
			var pan_speed := maxf(0.01, dist * 0.003)

			pivot.global_position += right * delta.x * pan_speed
			pivot.global_position -= up * delta.y * pan_speed

func handle_2d_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning_2d = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_2d(event.position, 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_2d(event.position, 1.0 / 1.1)

	elif event is InputEventMouseMotion and _is_panning_2d:
		var motion := event as InputEventMouseMotion
		var delta: Vector2 = motion.position - _last_mouse_pos
		_last_mouse_pos = motion.position
		texture_rect.position += delta

func _zoom_2d(mouse_pos: Vector2, factor: float) -> void:
	var old_scale := texture_rect.scale
	var new_scale := old_scale * factor

	new_scale.x = clampf(new_scale.x, 0.1, 50.0)
	new_scale.y = clampf(new_scale.y, 0.1, 50.0)

	var mouse_local := mouse_pos - texture_rect.position
	texture_rect.position -= mouse_local * ((new_scale / old_scale) - Vector2.ONE)
	texture_rect.scale = new_scale
