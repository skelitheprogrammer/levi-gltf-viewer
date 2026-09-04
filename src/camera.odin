package main

import "core:math/linalg"

Camera :: struct {
	aspect: f32,
	near:   f32,
	far:    f32,
	mode:   union {
		Orthographic,
		Perspective,
	},
}

Orthographic :: struct {
	size: f32,
}
Perspective :: struct {
	fov: f32,
}

get_view_proj :: proc(cam: Camera, pos: [3]f32, rot: linalg.Quaternionf32) -> matrix[4, 4]f32 {
	forward := linalg.mul(rot, [3]f32{0, 0, -1})
	view := linalg.matrix4_look_at(pos, pos + forward, [3]f32{0, 1, 0})

	bias: matrix[4, 4]f32 = linalg.MATRIX4F32_IDENTITY
	bias[2][2] = 0.5
	bias[3][2] = 0.5

	switch v in cam.mode {
	case Orthographic:
		proj := linalg.matrix_ortho3d(
			-cam.aspect * v.size,
			cam.aspect * v.size,
			-v.size,
			v.size,
			cam.near,
			cam.far,
		)
		proj[1][1] *= -1
		return bias * proj * view
	case Perspective:
		proj := linalg.matrix4_perspective(v.fov, cam.aspect, cam.near, cam.far)
		proj[1][1] *= -1
		return bias * proj * view
	}
	return linalg.MATRIX4F32_IDENTITY
}
