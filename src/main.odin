package main

import "../src/gpu/gpu"
import "base:runtime"
import log "core:log"
import sdl "vendor:sdl3"

GPU :: gpu.Memory.GPU

Start_Window_Size_X :: 1000
Start_Window_Size_Y :: 1000
Frames_In_Flight :: 3
Example_Name :: "3D"

main :: proc() {

	ok: bool

	console_logger := log.create_console_logger()
	defer log.destroy_console_logger(console_logger)
	context.logger = console_logger

	ok = sdl.Init({.VIDEO})
	window := sdl.CreateWindow(
		Example_Name,
		Start_Window_Size_X,
		Start_Window_Size_Y,
		{.VULKAN, .HIGH_PIXEL_DENSITY, .FULLSCREEN},
	)
	ensure(window != nil)

	ts_freq := sdl.GetPerformanceFrequency()
	max_delta_time: f32 = 1.0 / 10.0

	display_scale: f32 = sdl.GetWindowDisplayScale(window)

	window_size_x := i32(Start_Window_Size_X * display_scale)
	window_size_y := i32(Start_Window_Size_Y * display_scale)

	ok = gpu.init()
	ensure(ok)
	defer gpu.cleanup()

	gpu.swapchain_create_from_sdl(window, Frames_In_Flight)


	upload_arena := gpu.arena_create()
	defer gpu.arena_destroy(&upload_arena)


	mesh := create_triangle_mesh()

	mesh_gpu: Mesh_GPU
	defer mesh_destroy(&mesh_gpu)

	upload_cmd := gpu.commands_begin(.Main)

	upload_mesh(&upload_arena, upload_cmd, mesh)

	gpu.cmd_barrier(upload_cmd, .Transfer, .All, {})
	gpu.queue_submit(.Main, {upload_cmd})

	now_ts := sdl.GetPerformanceCounter()

	frame_arenas: [Frames_In_Flight]gpu.Arena
	for &frame_arena in frame_arenas do frame_arena = gpu.arena_create()
	defer for &frame_arena in frame_arenas do gpu.arena_destroy(&frame_arena)
	next_frame := u64(1)
	frame_sem := gpu.semaphore_create(0)
	defer gpu.semaphore_destroy(frame_sem)

	for handle_window_events() {

		old_window_size_x := window_size_x
		old_window_size_y := window_size_y
		sdl.GetWindowSizeInPixels(window, &window_size_x, &window_size_y)
		if .MINIMIZED in sdl.GetWindowFlags(window) || window_size_x <= 0 || window_size_y <= 0 {
			sdl.Delay(16)
			continue
		}

		if next_frame > Frames_In_Flight {
			gpu.semaphore_wait(frame_sem, next_frame - Frames_In_Flight)
		}
		if old_window_size_x != window_size_x || old_window_size_y != window_size_y {
			gpu.queue_wait_idle(.Main)
			gpu.swapchain_resize({u32(window_size_x), u32(window_size_y)})
		}

		swapchain := gpu.swapchain_acquire_next()
		if swapchain == {} {
			gpu.swapchain_resize({u32(window_size_x), u32(window_size_y)})
			continue
		}

		frame_arena := &frame_arenas[next_frame % Frames_In_Flight]
		gpu.arena_free_all(frame_arena)

		last_ts := now_ts
		now_ts = sdl.GetPerformanceCounter()
		delta_time := min(
			max_delta_time,
			f32(f64((now_ts - last_ts) * 1000) / f64(ts_freq)) / 1000.0,
		)

		cmd := gpu.commands_begin(.Main)
		gpu.cmd_begin_render_pass(
			cmd,
			{color_attachments = {{texture = swapchain, clear_color = {0.7, 0.7, 0.7, 1.0}}}},
		)


		Vert_Data :: struct #all_or_none {
			pos: rawptr,
			col: rawptr,
		}


		verts_data := gpu.arena_alloc(frame_arena, Vert_Data)
		verts_data.cpu^ = {
			pos = mesh_gpu[GPU_Stream.POS].ptr,
			col = mesh_gpu[GPU_Stream.COL].ptr,
		}

		gpu.cmd_draw_indexed_raw(cmd, verts_data, gpu.null, mesh_gpu[GPU_Stream.IDX], .U32, 3)

		gpu.cmd_end_render_pass(cmd)
		gpu.cmd_add_signal_semaphore(cmd, frame_sem, next_frame)
		gpu.queue_submit(.Main, {cmd})

		gpu.swapchain_present(.Main, frame_sem, next_frame)
		next_frame += 1
	}

	gpu.wait_idle()
}

GPU_Stream :: enum {
	POS,
	COL,
	UVS,
	IDX,
}

@(rodata)
GPU_Stream_Sizes := [GPU_Stream]i64 {
	.POS = size_of([4]f32),
	.COL = size_of([4]f32),
	.UVS = size_of([2]f32),
	.IDX = size_of(u32),
}

Stream :: struct {
	using slice: runtime.Raw_Slice,
	size:        i64,
}

Mesh :: distinct []Stream

Mesh_GPU :: distinct []gpu.gpuptr

upload_mesh :: proc(
	upload_arena: ^gpu.Arena,
	cmd: gpu.Command_Buffer,
	mesh: Mesh,
) -> (
	gpu_mesh: Mesh_GPU,
) {
	gpu_mesh = make(Mesh_GPU, len(mesh))
	for type in GPU_Stream {
		size := mesh[type].size
		count := mesh[type].len
		staging := gpu.arena_alloc_raw(upload_arena, size, count, 16)
		staging.cpu = &mesh[type].data
		gpu_mesh[type] = gpu.mem_alloc_raw(size, count, 16, GPU)
		gpu.cmd_mem_copy_raw(cmd, gpu_mesh[type], staging, size)
	}
	return
}

mesh_destroy :: proc(mesh: ^Mesh_GPU) {
	for type in GPU_Stream do if mesh[type] != gpu.null do gpu.mem_free_raw(mesh[type])
	mesh^ = {}
}

handle_window_events :: proc() -> bool {
	evt: sdl.Event
	for sdl.PollEvent(&evt) {
		#partial switch evt.type {
		case .QUIT:
			return false
		case .WINDOW_CLOSE_REQUESTED:
			sdl.Quit()
			return false
		case .KEY_DOWN:
			if evt.key.scancode == .F12 do return false
		}
	}

	return true
}

create_triangle_mesh :: proc() -> (mesh: Mesh) {
	mesh = make(Mesh, 3)
	pos := [?][4]f32{{-.5, -.5, 0, 1}, {0, .5, .0, 1}, {.5, -.5, 0, 1}}
	col := [?][4]f32{{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}
	idx := [?]u32{0, 1, 2}
	mesh[0] = Stream {
		data = raw_data(pos[:]),
		size = GPU_Stream_Sizes[.POS],
		len  = len(pos),
	}

	mesh[1] = Stream {
		data = raw_data(col[:]),
		size = GPU_Stream_Sizes[.COL],
		len  = len(col),
	}

	mesh[2] = Stream {
		data = raw_data(idx[:]),
		size = GPU_Stream_Sizes[.IDX],
		len  = len(idx),
	}

	return
}
