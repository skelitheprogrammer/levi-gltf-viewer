package renderer

import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"

Camera :: struct {
	pos:   linalg.Vector3f32,
	yaw:   f32,
	pitch: f32,
}


camera_get_front :: proc(cam: Camera) -> linalg.Vector3f32 {
	yaw_rad := math.to_radians_f32(cam.yaw)
	pitch_rad := math.to_radians_f32(cam.pitch)
	return linalg.Vector3f32 {
		math.cos(yaw_rad) * math.cos(pitch_rad),
		math.sin(pitch_rad),
		math.sin(yaw_rad) * math.cos(pitch_rad),
	}
}

camera_get_right :: proc(cam: Camera) -> linalg.Vector3f32 {
	front := camera_get_front(cam)
	up := linalg.Vector3f32{0, 1, 0}
	return linalg.cross(front, up)
}


camera_get_view_matrix :: proc(cam: Camera) -> glsl.mat4 {
	front := camera_get_front(cam)
	target := cam.pos + front
	up := linalg.Vector3f32{0, 1, 0}

	return glsl.mat4LookAt(cam.pos, target, up)
}

camera_get_projection_matrix :: proc(aspect: f32) -> glsl.mat4 {
	fov := math.to_radians_f32(60.0)

	return glsl.mat4Perspective(fov, aspect, 0.1, 1000.0)
}

camera_get_vp :: proc(cam: Camera, aspect: f32) -> [16]f32 {
	view := camera_get_view_matrix(cam)
	proj := camera_get_projection_matrix(aspect)
	vp := proj * view

	return transmute([16]f32)vp
}
