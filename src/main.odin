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

Buffer_Type :: enum {
	POS,
	COL,
	IDX,
}

@(rodata)
Buffer_Sizes := [Buffer_Type]i64 {
	.POS = size_of([4]f32),
	.COL = size_of([4]f32),
	.IDX = size_of(u32),
}

@(rodata)
Buffer_Aligns := [Buffer_Type]i64 {
	.POS = align_of([4]f32),
	.COL = align_of([4]f32),
	.IDX = align_of(u32),
}

@(rodata)
Buffer_Counts := [Buffer_Type]i64 {
	.POS = 1024,
	.COL = 1024,
	.IDX = 1024,
}

@(rodata)
Buffer_Memory := [Buffer_Type]gpu.Memory {
	.POS = .GPU,
	.COL = .GPU,
	.IDX = .GPU,
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

	renderer: Renderer
	renderer_init(&renderer, cast([2]u32)(win))
	defer renderer_destroy(&renderer)

	pool: Pool_State(Buffer_Type)
	pool_init(&pool, Buffer_Sizes, Buffer_Aligns, Buffer_Aligns, Buffer_Memory)

	opaque_pass_shaders := Shader_Pair{}
	defer for &s in opaque_pass_shaders do gpu.shader_destroy(s)

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

		handle_staging()

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
