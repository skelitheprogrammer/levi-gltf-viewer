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
Buffer_Memory := [Buffer_Type]gpu.Memory {
	.POS = .GPU,
	.COL = .GPU,
	.IDX = .GPU,
}

buffer_desc :: proc(type: Buffer_Type) -> Buffer_Desc {
	return {size = Buffer_Sizes[type], align = Buffer_Aligns[type], type = Buffer_Memory[type]}
}

buffer_descs :: proc(allocator := context.allocator) -> []Buffer_Desc {
	buffers := make([]Buffer_Desc, len(Buffer_Type), allocator)
	for type, i in Buffer_Type {
		buffers[i] = buffer_desc(type)
	}

	return buffers
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
	renderer_init(&renderer, buffer_descs(context.temp_allocator), cast([2]u32)(win))
	defer renderer_destroy(&renderer)

	upload_m: Upload_Manager
	upload_manager_init(&upload_m)

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

		update_memory(&upload_m)

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

Upload_Entry :: struct #all_or_none {
	ptr:   gpu.ptr,
	desc:  Buffer_Desc,
	bytes: i64,
}

Upload_Manager :: struct {
	entries: #soa[dynamic]Upload_Entry,
}

upload_manager_init :: proc(m: ^Upload_Manager, allocator := context.allocator) {
	m.entries = make(#soa[dynamic]Upload_Entry, allocator)
}

upload_memory :: proc(arena: ^gpu.Arena, manager: ^Upload_Manager, desc: Buffer_Desc, data: []u8) {
	ptr := gpu.arena_alloc_raw(arena, desc.size, desc.count, desc.align)
	ptr.cpu = raw_data(data)
	append(&manager.entries, Upload_Entry{ptr, desc, i64(len(data))})
}

update_memory :: proc(manager: ^Upload_Manager) {

	if len(manager.entries) == 0 do return

	upload_cmd := gpu.commands_begin(.Transfer)
	for entry in manager.entries {
		desc := entry.desc
		local := gpu.mem_alloc_raw(desc.size, desc.count, desc.align, .GPU)
		gpu.cmd_mem_copy_raw(upload_cmd, local, entry.ptr, entry.bytes)
	}


	clear(&manager.entries)

	gpu.cmd_barrier(upload_cmd, .Transfer, .All)
	gpu.queue_submit(.Transfer, {upload_cmd})
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
