package main

import "core:math/linalg"
import sdl "vendor:sdl3"

Input_State :: struct {
	mouse_dx, mouse_dy: f32,
	keys_pressed:       [dynamic]bool,
}

Camera_State :: struct {
	pos:   [3]f32,
	angle: [2]f32,
	rot:   linalg.Quaternionf32,
}

update_camera :: proc(cam: ^Camera_State, input: ^Input_State, dt: f32) {
	mouse_sensitivity: f32 = 0.002

	cam.angle.x -= input.mouse_dx * mouse_sensitivity
	cam.angle.y -= input.mouse_dy * mouse_sensitivity
	cam.angle.y = clamp(cam.angle.y, -1.5, 1.5)

	move_speed: f32 = 2.0
	move_dir: [3]f32

	is_pressed :: proc(input: ^Input_State, key: sdl.Scancode) -> bool {
		idx := int(key)
		if idx >= len(input.keys_pressed) do return false
		return input.keys_pressed[idx]
	}

	if is_pressed(input, .W) do move_dir.z += 1
	if is_pressed(input, .S) do move_dir.z -= 1
	if is_pressed(input, .D) do move_dir.x -= 1
	if is_pressed(input, .A) do move_dir.x += 1
	if is_pressed(input, .E) do move_dir.y += 1
	if is_pressed(input, .Q) do move_dir.y -= 1

	if linalg.dot(move_dir, move_dir) > 0 do move_dir = linalg.normalize(move_dir)

	pitch_rot := linalg.quaternion_angle_axis(cam.angle.y, [3]f32{1, 0, 0})
	yaw_rot := linalg.quaternion_angle_axis(cam.angle.x, [3]f32{0, 1, 0})
	cam.rot = yaw_rot * pitch_rot

	world_move_dir := linalg.mul(cam.rot, move_dir)
	cam.pos += world_move_dir * (move_speed * dt)
}

poll_window_events :: proc(window: ^sdl.Window, input: ^Input_State) -> (proceed: bool) {
	input.mouse_dx = 0
	input.mouse_dy = 0
	evt: sdl.Event
	proceed = true
	for sdl.PollEvent(&evt) {
		#partial switch evt.type {
		case .QUIT:
			proceed = false
		case .KEY_DOWN:
			if evt.key.scancode == .F12 do proceed = false
			else {
				idx := int(evt.key.scancode)
				for len(input.keys_pressed) <= idx do append(&input.keys_pressed, false)
				input.keys_pressed[idx] = true
			}
		case .KEY_UP:
			idx := int(evt.key.scancode)
			for len(input.keys_pressed) <= idx do append(&input.keys_pressed, false)
			input.keys_pressed[idx] = false
		case .WINDOW_CLOSE_REQUESTED:
			if evt.window.windowID == sdl.GetWindowID(window) do proceed = false
		case .MOUSE_MOTION:
			input.mouse_dx += evt.motion.xrel
			input.mouse_dy += evt.motion.yrel
		}
	}
	return
}
