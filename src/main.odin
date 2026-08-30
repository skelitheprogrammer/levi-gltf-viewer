package main

import gpu "../src/gpu/gpu"
import levi "../src/levi"

import "core:log"
import "core:math/linalg"

import sdl "vendor:sdl3"

SCREEN_WIDTH :: 1280
SCREEN_HEIGHT :: 720

INSTANCE_COUNT :: 3


State :: struct {
	positions: [dynamic][3]f32,
	rotations: [dynamic]quaternion128,
	scale:     [dynamic][3]f32,
}

main :: proc() {
	logger := log.create_console_logger(.Info)
	context.logger = logger
	defer log.destroy_console_logger(logger)

	ok: bool

	ok = sdl.Init({.VIDEO}); ensure(ok, "sdl is not initialized"); defer sdl.Quit()

	window := sdl.CreateWindow(
		"Levi Viewer",
		SCREEN_WIDTH,
		SCREEN_HEIGHT,
		{.VULKAN, .RESIZABLE, .HIGH_PIXEL_DENSITY},
	); ensure(window != nil, "Window creation failed"); defer sdl.DestroyWindow(window)


	display_size := sdl.GetWindowDisplayScale(window)
	win_s := [2]i32{i32(SCREEN_WIDTH * display_size), i32(SCREEN_HEIGHT * display_size)}

	ok = gpu.init(); ensure(ok, "gpu is not initialized"); defer gpu.cleanup()
	gpu.swapchain_create_from_sdl(window, u32(levi.FLIGHT))

	state: levi.Render_State
	levi.render_init(&state); defer levi.render_destroy(&state)

	shaders := levi.Shader_Pair {
		.Vertex   = gpu.shader_create(#load("../samples/triangle/unlit.vert.spv", []u32), .Vertex),
		.Fragment = gpu.shader_create(
			#load("../samples/triangle/unlit.frag.spv", []u32),
			.Fragment,
		),
	}

	defer for shader in shaders do gpu.shader_destroy(shader)

	cam := Camera {
		mode = Perspective{fov = linalg.to_radians(f32(45.0))},
		aspect = f32(win_s[0]) / f32(win_s[1]),
		near = 0.1,
		far = 100.0,
	}
	cam_pos := [3]f32{0, 0, -3}
	cam_rot := linalg.QUATERNIONF32_IDENTITY

	pool: levi.Geometry_Pool
	levi.geometry_pool_init(&pool, {})

	staging := levi.geometry_begin_upload(&pool)
	create_triangle(&staging)
	levi.geometry_submit(&staging)

	for {
		if !poll_window_events(window) do break

		frame_idx := state.next_frame % levi.FLIGHT

		handle_window_resize(window, &win_s[0], &win_s[1], frame_idx, state.frame_sem)

		if .MINIMIZED in sdl.GetWindowFlags(window) || win_s[0] <= 0 || win_s[1] <= 0 {
			sdl.Delay(16)
			continue
		}
	}
	gpu.wait_idle()
}

poll_window_events :: proc(window: ^sdl.Window) -> (proceed: bool) {
	evt: sdl.Event

	proceed = true

	for sdl.PollEvent(&evt) {
		#partial switch evt.type {
		case .QUIT:
			proceed = false
		case .KEY_DOWN:
			if evt.key.scancode == .F12 do proceed = false
		case .WINDOW_CLOSE_REQUESTED:
			if evt.window.windowID == sdl.GetWindowID(window) do proceed = false
		}
	}

	return
}

handle_window_resize :: proc(
	window: ^sdl.Window,
	width, height: ^i32,
	frame_idx: u64,
	frame_sem: gpu.Semaphore,
) {
	old_ws := [2]i32{width^, height^}

	sdl.GetWindowSizeInPixels(window, width, height)

	if frame_idx > levi.FLIGHT do gpu.semaphore_wait(frame_sem, frame_idx - levi.FLIGHT)
	if old_ws != {width^, height^} do gpu.swapchain_resize({u32(max(0, width^)), u32(max(0, height^))})

}


create_triangle :: proc(staging: ^levi.Geometry_Staging) {

	triangle_pos := [][4]f32{{-1, -1, 0, 1}, {0, 1, 0, 1}, {1, -1, 0, 1}}
	triangle_colors := [][4]f32{{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}
	triangle_indices := []u32{0, 1, 2}

	triangle_mat := Unlit_Material {
		base_color = {1, 0, 0, 1},
	}

	ptrs := levi.geometry_append(
		staging,
		{
			.Position = levi.Geometry_Stream {
				data = raw_data(triangle_pos[:]),
				count = i64(len(triangle_pos)),
			},
			.Color = levi.Geometry_Stream {
				data = raw_data(triangle_colors[:]),
				count = i64(len(triangle_colors)),
			},
		},
	)

	return
}

calculate_model :: #force_inline proc "contextless" (
	pos: [3]f32,
	rot: quaternion128,
	scale: [3]f32,
) -> matrix[4, 4]f32 {
	return linalg.matrix4_from_trs_f32(pos, rot, scale)
}
