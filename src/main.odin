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

Default_Config := Config{"TheGame", 3440, 1440}


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

	renderer: Renderer
	renderer_init(&renderer, cast([2]u32)(win))
	defer renderer_destroy(&renderer)

	buffers: Buffers
	buffers_init(&buffers, 1024)

	opaque_pass_shaders := Shader_Pair{}
	defer for &s in opaque_pass_shaders do gpu.shader_destroy(s)

	init_data(&buffers)

	ts_freq := sdl.GetPerformanceFrequency()
	last_ts := sdl.GetPerformanceCounter()


	for handle_window_events() {
		sdl.GetWindowSizeInPixels(window, &win.x, &win.y)
		if .MINIMIZED in sdl.GetWindowFlags(window) || win.x <= 0 || win.y <= 0 {
			sdl.Delay(16)
			continue
		}

		now_ts := sdl.GetPerformanceCounter()
		last_ts = now_ts

		cmd, swapchain, arena := frame_begin(&renderer, win) or_break


		opaque_pass(cmd, swapchain, arena, opaque_pass_shaders)

		frame_end(&renderer, cmd)

	}

	gpu.wait_idle()
}

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


init_data :: proc(b: ^Buffers) {
	upload := gpu.arena_create()
	defer gpu.arena_destroy(&upload)
	cmd := gpu.commands_begin(.Transfer)


	gpu.cmd_barrier(cmd, .Transfer, .All)
	gpu.queue_submit(.Main, {cmd})
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
