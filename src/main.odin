package main

import gpu "../src/gpu/gpu"
import levi "../src/levi"
import intr "base:intrinsics"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import sdl "vendor:sdl3"

// USER: Define your own application data structures
My_Instance :: struct {
	pos:   [3]f32,
	color: [4]f32,
}

App_State :: struct {
	instances: [dynamic]My_Instance,
}

// USER: Implement extraction - you handle the math
extract :: proc(id: levi.Instance_ID, user_data: rawptr) -> levi.Extract_Result {
	state := cast(^App_State)user_data
	inst := state.instances[id]

	// USER: Calculate your own transform matrix
	mat4 := linalg.matrix4_from_trs_f32(inst.pos, linalg.QUATERNIONF32_IDENTITY, {1, 1, 1})

	return levi.Extract_Result {
		transform = intr.matrix_flatten(mat4),
		params = levi.Material_Params{base_color = inst.color, emissive = {0, 0, 0, 0}},
	}
}

// USER: Define your own render pass
my_opaque_pass :: proc(ctx: ^levi.Render_Context) {
	r := ctx.renderer
	if len(r.instances) == 0 do return

	mat_id := r.instances[0].material_id
	mat := r.materials[mat_id]
	gpu.cmd_set_shaders(ctx.cmd_buf, r.shaders[mat.vert], r.shaders[mat.frag])
	gpu.cmd_set_raster_state(
		ctx.cmd_buf,
		gpu.Raster_State{topology = .Triangle_List, cull_mode = .None},
	)

	root := gpu.arena_alloc(ctx.frame_arena, levi.Vertex_Root)
	for attr in levi.Vertex_Attribute {
		root.cpu.attributes[attr] = r.streams[levi.Stream_Attribute(attr)].ptr
	}
	root.cpu.instances = r.streams[.Instances].ptr
	root.cpu.material_params = r.streams[.Material_Params_Stream].ptr
	root.cpu.frame_data = r.streams[.Frame_Data_Stream].ptr

	gpu.cmd_begin_render_pass(
		ctx.cmd_buf,
		{color_attachments = {{texture = ctx.target, clear_color = {0.15, 0.15, 0.15, 1.0}}}},
	)

	gpu.cmd_draw_indexed_indirect_multi_raw(
		ctx.cmd_buf,
		root.gpu,
		{},
		r.streams[.Indices],
		.U32,
		r.streams[.Indirect_Commands],
		u32(size_of(gpu.Draw_Indexed_Indirect_Command)),
		r.streams[.Draw_Count],
	)

	gpu.cmd_end_render_pass(ctx.cmd_buf)
}

// USER: Create your own mesh content
create_quad :: proc(eng: ^levi.Engine) -> levi.Mesh_ID {
	pos := make([][4]f32, 4)
	pos[0] = {-0.5, -0.5, 0, 1}; pos[1] = {0.5, -0.5, 0, 1}
	pos[2] = {0.5, 0.5, 0, 1}; pos[3] = {-0.5, 0.5, 0, 1}

	col := make([][4]f32, 4)
	for i in 0 ..< 4 do col[i] = {1, 1, 1, 1}

	idx := make([]u32, 6)
	idx[0] = 0; idx[1] = 1; idx[2] = 2
	idx[3] = 0; idx[4] = 2; idx[5] = 3

	return levi.create_mesh(
		eng,
		levi.Mesh_Desc {
			attributes = #partial{
				.Position = mem.slice_to_bytes(pos[:]),
				.Color = mem.slice_to_bytes(col[:]),
			},
			indices = idx,
		},
	)
}

// USER: Calculate your own view-projection matrix
calculate_view_proj :: proc(eye, target, up: [3]f32, fov, aspect, near, far: f32) -> [16]f32 {
	view := linalg.matrix4_look_at_f32(eye, target, up, false)
	proj := linalg.matrix4_perspective_f32(math.RAD_PER_DEG * fov, aspect, near, far, false)

	// Apply Vulkan depth bias [0, 1]
	bias: matrix[4, 4]f32 = linalg.MATRIX4F32_IDENTITY
	bias[2][2] = 0.5
	bias[2][3] = 0.5
	proj = proj * bias

	vp := proj * view
	return intr.matrix_flatten(vp)
}

main :: proc() {
	logger := log.create_console_logger(.Info)
	context.logger = logger
	defer log.destroy_console_logger(logger)

	ok := sdl.Init({.VIDEO})
	ensure(ok, "sdl is not initialized")
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Levi Viewer",
		1280,
		720,
		{.VULKAN, .RESIZABLE, .HIGH_PIXEL_DENSITY},
	)
	ensure(window != nil)
	defer sdl.DestroyWindow(window)

	eng := levi.engine_init(window, 1280, 720)
	defer levi.engine_destroy(eng)

	app: App_State

	vert := levi.create_shader(eng, #load("../samples/triangle/unlit.vert.spv", []u32), .Vertex)
	frag := levi.create_shader(eng, #load("../samples/triangle/unlit.frag.spv", []u32), .Fragment)
	mat := levi.create_material(eng, vert, frag, params_size = size_of(levi.Material_Params))
	mesh := create_quad(eng)

	levi.spawn_instance(eng, mesh, mat)
	append(&app.instances, My_Instance{pos = {0, 0, 0}, color = {1, 0, 0, 1}})

	levi.spawn_instance(eng, mesh, mat)
	append(&app.instances, My_Instance{pos = {0.5, 0, 0}, color = {0, 1, 0, 1}})

	eng.extract = extract
	eng.user_data = &app
	append(&eng.passes, my_opaque_pass)

	frame_data: levi.Frame_Data

	for {
		if !poll_window_events(window) do break

		w, h: i32
		sdl.GetWindowSizeInPixels(window, &w, &h)
		eng.win_s = {w, h}

		if eng.win_s[0] == 0 || eng.win_s[1] == 0 do continue

		aspect := f32(eng.win_s[0]) / f32(eng.win_s[1])
		frame_data.view_proj = calculate_view_proj(
			{0, 0, -3},
			{0, 0, 0},
			{0, 1, 0},
			45.0,
			aspect,
			0.1,
			100.0,
		)

		levi.draw(eng, &frame_data)
	}
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
