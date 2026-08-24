package levi

import "core:math/linalg"

Camera :: struct {
	position: linalg.Vector3f32,
	forward:  linalg.Vector3f32,
	up:       linalg.Vector3f32,
	fov:      f32,
	aspect:   f32,
	near:     f32,
	far:      f32,
}

get_view_proj :: proc(cam: Camera) -> linalg.Matrix4f32 {
	view := linalg.matrix4_look_at(cam.position, cam.position + cam.forward, cam.up)
	proj := linalg.matrix4_perspective(cam.fov, cam.aspect, cam.near, cam.far)
	return linalg.matrix_mul(proj, view)
}
