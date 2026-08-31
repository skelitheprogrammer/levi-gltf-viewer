package main

import gpu "../src/gpu/gpu"
import levi "../src/levi"
import "core:log"
import "core:math/linalg"

import sdl "vendor:sdl3"

SCREEN_WIDTH :: 1280
SCREEN_HEIGHT :: 720

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
		{.VULKAN, .RESIZABLE},
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

	meshes: [2]levi.Mesh

	staging := levi.geometry_begin_upload(&pool)
	meshes[0] = create_triangle_1(&staging)
	meshes[1] = create_triangle_2(&staging)
	levi.geometry_submit(&staging)

	// 2 instances of mesh 0 on the left, 3 of mesh 1 on the right
	draws: [dynamic]levi.Draw
	defer delete(draws)
	{
		id := linalg.QUATERNIONF32_IDENTITY
		for i in 0 ..< 2 {
			append(
				&draws,
				levi.Draw {
					mesh = 0,
					model = calculate_model({-1.5, f32(i) * 0.8 - 0.4, 0}, id, {0.35, 0.35, 0.35}),
				},
			)
		}
		for i in 0 ..< 3 {
			append(
				&draws,
				levi.Draw {
					mesh = 1,
					model = calculate_model({1.5, f32(i) * 0.8 - 0.8, 0}, id, {0.35, 0.35, 0.35}),
				},
			)
		}
	}

	for {
		if !poll_window_events(window) do break

		handle_window_resize(
			window,
			&win_s[0],
			&win_s[1],
			state.next_frame % levi.FLIGHT,
			state.frame_sem,
		)

		if .MINIMIZED in sdl.GetWindowFlags(window) || win_s[0] <= 0 || win_s[1] <= 0 {
			sdl.Delay(16)
			continue
		}

		draw(&state, meshes[:], draws[:], shaders, get_view_proj(cam, cam_pos, cam_rot), win_s)
		state.next_frame += 1
	}

	gpu.wait_idle()
}

draw :: proc(
	state: ^levi.Render_State,
	meshes: []levi.Mesh,
	draws: []levi.Draw,
	pair: levi.Shader_Pair,
	view_proj: matrix[4, 4]f32,
	win_size: [2]i32,
) {
	// don't overwrite an in-flight frame before reusing its arena
	if state.next_frame > levi.FLIGHT do gpu.semaphore_wait(state.frame_sem, state.next_frame - levi.FLIGHT)

	swapchain := gpu.swapchain_acquire_next()
	arena := levi.acquire_frame_arena(state, int(state.next_frame % levi.FLIGHT))
	cmd := gpu.commands_begin(.Main)

	frame := gpu.arena_alloc(arena, levi.Frame_Data)
	frame.cpu^ = levi.Frame_Data {
		view_proj = view_proj,
	}

	// group instances by mesh so each mesh's run is contiguous (one instanced draw per run)

	inst := gpu.arena_alloc(arena, levi.Instance_Data, len(draws))
	insts := inst.cpu[:len(draws)]
	for d, i in draws {
		insts[i] = levi.Instance_Data {
			model = d.model,
		}
	}

	gpu.cmd_begin_render_pass(
		cmd,
		{color_attachments = {{texture = swapchain, clear_color = {.1, .1, .1, 1}}}},
	)
	gpu.cmd_set_viewport(cmd, {size = {f32(win_size[0]), f32(win_size[1])}, depth_max = 1})
	gpu.cmd_set_scissor(cmd, {size = {u32(win_size[0]), u32(win_size[1])}})
	gpu.cmd_set_shaders(cmd, pair[.Vertex], pair[.Fragment])
	gpu.cmd_set_raster_state(cmd, {topology = .Triangle_List, cull_mode = .Cull_CW})

	i := 0
	for i < len(draws) {
		mesh_id := draws[i].mesh
		j := i + 1
		for j < len(draws) && draws[j].mesh == mesh_id do j += 1

		mesh := &meshes[mesh_id]
		root_alloc := gpu.arena_alloc(arena, levi.Unlit_Vertex_Root)
		root_alloc.cpu.streams[.Position] = mesh.streams[.Position].ptr
		root_alloc.cpu.streams[.Color] = mesh.streams[.Color].ptr
		root_alloc.cpu.instances = rawptr(
			uintptr(inst.gpu.ptr) + uintptr(i * size_of(levi.Instance_Data)),
		)
		root_alloc.cpu.frame = frame.gpu.ptr

		gpu.cmd_draw(cmd, root_alloc.gpu, gpu.null, mesh.vertex_count, u32(j - i))
		i = j
	}

	gpu.cmd_end_render_pass(cmd)
	gpu.cmd_add_signal_semaphore(cmd, state.frame_sem, state.next_frame)
	gpu.queue_submit(.Main, {cmd})
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

create_triangle_1 :: proc(staging: ^levi.Geometry_Staging) -> levi.Mesh {
	triangle_pos := [][4]f32{{-1, -1, 0, 1}, {0, 1, 0, 1}, {1, -1, 0, 1}}
	triangle_colors := [][4]f32{{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}

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

	return levi.Mesh{streams = ptrs, vertex_count = u32(len(triangle_pos))}
}

create_triangle_2 :: proc(staging: ^levi.Geometry_Staging) -> levi.Mesh {
	triangle_pos := [][4]f32{{-1, -1, 0, 1}, {-1, 1, 0, 1}, {1, -1, 0, 1}}
	triangle_colors := [][4]f32{{0, 1, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}

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

	return levi.Mesh{streams = ptrs, vertex_count = u32(len(triangle_pos))}
}

calculate_model :: #force_inline proc "contextless" (
	pos: [3]f32,
	rot: quaternion128,
	scale: [3]f32,
) -> matrix[4, 4]f32 {
	return linalg.matrix4_from_trs_f32(pos, rot, scale)
}
