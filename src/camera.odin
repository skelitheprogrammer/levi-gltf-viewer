package main

import "core:math/linalg"

Camera_Mode :: union {
	Orthographic,
	Perspective,
}

Orthographic :: struct {
	width:  f32,
	height: f32,
}

Perspective :: struct {
	fov: f32,
}

Camera :: struct {
	mode:              Camera_Mode,
	aspect, near, far: f32,
}

get_view_proj :: proc(cam: Camera, pos: [3]f32, rot: quaternion128) -> matrix[4, 4]f32 {
	forward := linalg.mul(rot, [3]f32{0, 0, -1})
	view := linalg.matrix4_look_at(pos, forward, [3]f32{0, 1, 0})

	switch v in cam.mode {
	case Orthographic:
		proj := linalg.matrix_ortho3d(
			-v.width * 0.5,
			v.width * 0.5,
			-v.height * 0.5,
			v.height * 0.5,
			cam.near,
			cam.far,
		)
		return proj * view
	case Perspective:
		proj := linalg.matrix4_perspective(v.fov, cam.aspect, cam.near, cam.far)
		return proj * view
	}

	return linalg.MATRIX4F32_IDENTITY
}
