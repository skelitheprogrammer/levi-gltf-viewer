package main

import gpu "../src/gpu/gpu"
import levi "../src/levi"

import "core:log"
import "core:math/linalg"

import sdl "vendor:sdl3"

SCREEN_WIDTH :: 1280
SCREEN_HEIGHT :: 720

INSTANCE_COUNT :: 3

main :: proc() {
	logger := log.create_console_logger(.Info)

	context.logger = logger

	defer log.destroy_console_logger(logger)

	ok := gpu.init()

	ensure(ok, "gpu is not initialized")

	defer gpu.cleanup()

	ok = sdl.Init({.VIDEO})

	ensure(ok, "sdl is not initialized")

	defer sdl.Quit()

	window := sdl.CreateWindow("Levi Viewer", SCREEN_WIDTH, SCREEN_HEIGHT, {.VULKAN, .FULLSCREEN})

	ensure(window != nil, "Window creation failed")

	defer sdl.DestroyWindow(window)

	gpu.swapchain_create_from_sdl(window, u32(levi.FLIGHT))

	state: levi.Render_State

	levi.render_init(&state)

	defer levi.render_destroy(&state)

	geom := upload_triangle_example(&state)

	defer levi.geometry_destroy(&geom)

	shaders := levi.Shader_Pair {
		.Vertex   = gpu.shader_create(#load("../samples/triangle/unlit.vert.spv", []u32), .Vertex),
		.Fragment = gpu.shader_create(
			#load("../samples/triangle/unlit.frag.spv", []u32),
			.Fragment,
		),
	}

	defer for shader in shaders {
		gpu.shader_destroy(shader)
	}

	cam := Camera {
		mode = Perspective{fov = linalg.to_radians(f32(45.0))},
		aspect = f32(SCREEN_WIDTH) / f32(SCREEN_HEIGHT),
		near = 0.1,
		far = 100.0,
	}

	cam_pos := [3]f32{0, 0, -3}

	cam_rot := linalg.QUATERNIONF32_IDENTITY

	win_w: i32 = SCREEN_WIDTH
	win_h: i32 = SCREEN_HEIGHT

	for {
		proceed, did_resize := poll_window_events(window, &win_w, &win_h)

		if !proceed {
			break
		}

		if .MINIMIZED in sdl.GetWindowFlags(window) {
			sdl.Delay(16)
			continue
		}

		if win_w <= 0 || win_h <= 0 {
			sdl.Delay(16)
			continue
		}

		if did_resize {
			gpu.wait_idle()

			gpu.swapchain_resize({u32(win_w), u32(win_h)})

			cam.aspect = f32(win_w) / f32(win_h)

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
			if evt.key.scancode == .F12 {
				proceed = false
			}

		case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
			old_w := win_w^
			old_h := win_h^

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

	instances := gpu.arena_alloc_slice(arena, levi.Instance_Data, INSTANCE_COUNT)

	instances.cpu[0].transform = linalg.matrix4_translate([3]f32{-1.5, 0, 0})

	instances.cpu[1].transform = linalg.matrix4_translate([3]f32{0, 0, 0})

	instances.cpu[2].transform = linalg.matrix4_translate([3]f32{1.5, 0, 0})

	draw_data := gpu.arena_alloc_ptr(arena, levi.Draw_Data)

	draw_data.cpu^ = {}

	draw_data.cpu^.frame_data = u64(uintptr(fd_block.gpu.ptr))

	draw_data.cpu^.instance_data = u64(uintptr(instances.gpu.ptr))

	draw_data.cpu^.position = u64(uintptr(geometry.position.ptr))

	for attr in levi.Vertex_Attribute {
		draw_data.cpu^.attributes[attr] = u64(uintptr(geometry.attributes[attr].ptr))
	}

	cmd := gpu.commands_begin(.Main)

	levi.render_geometry(state, draw_data.gpu, geometry, swapchain, pair, cmd, INSTANCE_COUNT)

	gpu.cmd_add_signal_semaphore(cmd, state.frame_sem, state.next_frame)

	gpu.queue_submit(.Main, {cmd})

	gpu.swapchain_present(.Main, state.frame_sem, state.next_frame)

	state.arena_done[frame_idx] = state.next_frame

	state.next_frame += 1
}

upload_triangle_example :: proc(state: ^levi.Render_State) -> levi.Geometry {
	triangle_pos := [?][4]f32{{-1, -1, 0, 1}, {0, 1, 0, 1}, {1, -1, 0, 1}}

	triangle_colors := [?][4]f32{{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}

	triangle_indices := [?]u32{0, 1, 2}

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
