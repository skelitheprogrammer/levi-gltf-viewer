package main

import "../src/gpu/gpu"
import "base:runtime"
import "core:c"
import "core:flags"
import log "core:log"
import "core:os"
import sdl "vendor:sdl3"


Config :: struct {
	name: cstring,
	w:    c.int,
	h:    c.int,
}

Scene :: struct {
	mesh:        Mesh_GPU,
	index_count: u32,
}

Default_Config := Config{"TheGame", 3440, 1440}

init_window :: proc() -> (window: ^sdl.Window) {
	window = sdl.CreateWindow(
		Default_Config.name,
		Default_Config.w,
		Default_Config.h,
		{.VULKAN, .HIGH_PIXEL_DENSITY, .FULLSCREEN},
	)
	ensure(window != nil)

	return
}

main :: proc() {
	flags.parse_or_exit(&Default_Config, os.args)


	console_logger := log.create_console_logger()
	defer log.destroy_console_logger(console_logger)
	context.logger = console_logger

	ensure(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := init_window()
	defer sdl.DestroyWindow(window)

	scale := sdl.GetWindowDisplayScale(window)
	win := [2]i32{i32(f32(Default_Config.w) * scale), i32(f32(Default_Config.h) * scale)}

	ensure(gpu.init())
	defer gpu.cleanup()
	gpu.swapchain_create_from_sdl(window, FLIGHT)

	frames: Renderer
	renderer_init(&frames, cast([2]u32)(win))
	defer renderer_destroy(&frames)

	scene: Scene
	{
		upload_arena := gpu.arena_create()
		defer gpu.arena_destroy(&upload_arena)

		mesh := create_triangle_mesh()
		cmd := gpu.commands_begin(.Main)
		scene.mesh = mesh_upload(&upload_arena, cmd, mesh)
		scene.index_count = u32(mesh[.IDX].len)
		gpu.cmd_barrier(cmd, .Transfer, .All, {})
		gpu.queue_submit(.Main, {cmd})
		gpu.wait_idle()
	}
	defer mesh_destroy(&scene.mesh)

	// Frame loop
	ts_freq := sdl.GetPerformanceFrequency()
	last_ts := sdl.GetPerformanceCounter()
	max_dt: f64 = 0.1

	for handle_window_events() {
		sdl.GetWindowSizeInPixels(window, &win_x, &win_y)
		if .MINIMIZED in sdl.GetWindowFlags(window) || win_x <= 0 || win_y <= 0 {
			sdl.Delay(16)
			continue
		}

		now_ts := sdl.GetPerformanceCounter()
		last_ts = now_ts

		draw(&frames)
	}

	gpu.wait_idle()
}

draw :: proc(frames: ^Renderer, win: [2]i32, scene: ^Scene) {
	cmd, target, arena, ok := frame_begin(frames, win)
	if !ok {
		sdl.Delay(16)
		return
	}
	opaque_pass(cmd, target, arena, scene)
	frame_end(frames, cmd)
}


handle_window_events :: proc() -> bool {
	evt: sdl.Event
	for sdl.PollEvent(&evt) {
		#partial switch evt.type {
		case .QUIT:
			return false
		case .WINDOW_CLOSE_REQUESTED:
			sdl.Quit(); return false
		case .KEY_DOWN:
			if evt.key.scancode == .F12 do return false
		}
	}
	return true
}
