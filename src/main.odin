package main

import gpu "../src/gpu/gpu"
import levi "../src/levi"
import "core:log"
import "core:math/linalg"
import sdl "vendor:sdl3"

main :: proc() {
	logger := log.create_console_logger(.Info)
	context.logger = logger
	defer log.destroy_console_logger(logger)

	ok := gpu.init(); ensure(ok, "gpu is not initialized"); defer gpu.cleanup()
	ok = sdl.Init({.VIDEO}); ensure(ok, "sdl is not initialized"); defer sdl.Quit()

	window := sdl.CreateWindow("Levi Viewer", 1280, 720, {.VULKAN, .RESIZABLE})
	ensure(window != nil, "Window creation failed"); defer sdl.DestroyWindow(window)

	win_w, win_h: i32 = 1280, 720
	gpu.swapchain_create_from_sdl(window, u32(levi.FLIGHT))

	state: levi.Render_State
	levi.render_init(&state); defer levi.render_destroy(&state)
	defer gpu.wait_idle()

	geom := upload_triangle_example(&state)

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
		aspect = f32(win_w) / f32(win_h),
		near = 0.1,
		far = 100.0,
	}
	cam_pos := [3]f32{0, 0, 3}
	cam_rot := linalg.QUATERNIONF32_IDENTITY

	for {
		proceed, did_resize := poll_window_events(window, &win_w, &win_h)
		if !proceed do break

		if did_resize {
			gpu.wait_idle()
			gpu.swapchain_resize({u32(max(0, win_w)), u32(max(0, win_h))})
			cam.aspect = f32(win_w) / f32(win_h)
			continue
		}


		if .MINIMIZED in sdl.GetWindowFlags(window) || win_w <= 0 || win_h <= 0 {
			sdl.Delay(16)
			continue
		}

		render_frame(&state, &geom, shaders, cam, cam_pos, cam_rot)
	}
}

poll_window_events :: proc(
	window: ^sdl.Window,
	win_w, win_h: ^i32,
) -> (
	proceed: bool,
	did_resize: bool,
) {
	evt: sdl.Event
	proceed = true
	did_resize = false

	for sdl.PollEvent(&evt) {
		#partial switch evt.type {
		case .QUIT:
			proceed = false
		case .KEY_DOWN:
			if evt.key.scancode == .F12 do proceed = false


		case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
			old_w, old_h := win_w^, win_h^
			sdl.GetWindowSize(window, win_w, win_h)
			if old_w != win_w^ || old_h != win_h^ {
				did_resize = true
			}
		}
	}
	return
}

render_frame :: proc(
	state: ^levi.Render_State,
	geometry: ^levi.Geometry,
	pair: levi.Shader_Pair,
	cam: Camera,
	cam_pos: [3]f32,
	cam_rot: linalg.Quaternionf32,
) {
	levi.pump_uploads(state)

	swapchain := gpu.swapchain_acquire_next()

	frame_idx := int(state.next_frame % levi.FLIGHT)
	arena := levi.acquire_frame_arena(state, frame_idx)

	fd_block := state.frame_data_blocks[frame_idx]
	fd_block.cpu^.view_proj = get_view_proj(cam, cam_pos, cam_rot)

	vd := gpu.arena_alloc_ptr(arena, levi.Geometry_Vertex_Data)
	vd.cpu^ = {}
	vd.cpu^.frame_data = u64(uintptr(fd_block.gpu.ptr))
	vd.cpu^.position = u64(uintptr(geometry.position.ptr))
	for attr in levi.Vertex_Attribute {
		vd.cpu^.attributes[attr] = u64(uintptr(geometry.attributes[attr].ptr))
	}

	cmd := gpu.commands_begin(.Main)
	levi.render_geometry(state, vd.gpu, geometry, swapchain, pair, cmd)

	gpu.cmd_add_signal_semaphore(cmd, state.frame_sem, state.next_frame)
	gpu.queue_submit(.Main, {cmd})
	gpu.swapchain_present(.Main, state.frame_sem, state.next_frame)

	state.arena_done[frame_idx] = state.next_frame
	state.next_frame += 1
}

upload_triangle_example :: proc(state: ^levi.Render_State) -> levi.Geometry {
	triangle_pos := [?][4]f32{{-1, -1, 0, 1}, {0, 1, 0, 1}, {1, -1, 0, 1}}
	triangle_colors := [?][4]f32{{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}
	triangle_indices := [?]u32{0, 2, 1}

	desc: levi.Geometry_Desc
	desc.index_format = .U32

	desc.positions = {
		data   = raw_data(triangle_pos[:]),
		count  = len(triangle_pos),
		stride = size_of([4]f32),
	}
	desc.attributes[.COLOR] = {
		data   = raw_data(triangle_colors[:]),
		count  = len(triangle_colors),
		stride = size_of([4]f32),
	}
	desc.indices = {
		data   = raw_data(triangle_indices[:]),
		count  = len(triangle_indices),
		stride = size_of(u32),
	}

	return levi.upload_geometry(state, desc)
}
