package main

import gpu "../src/gpu/gpu"
import levi "../src/levi"
import "core:log"
import "core:math/linalg"
import sdl "vendor:sdl3"

My_Instance :: struct {
	pos:   [3]f32,
	vel:   [3]f32,
	color: [4]f32,
}

App_State :: struct {
	instances: [dynamic]My_Instance,
	vert:      levi.Shader_ID,
	frag:      levi.Shader_ID,
	mat:       levi.Material_ID,
}

extract :: proc(id: levi.Instance_ID, user_data: rawptr) -> levi.Extract_Result {
	state := cast(^App_State)user_data
	inst := state.instances[id]
	return levi.Extract_Result {
		transform = linalg.matrix4_from_trs_f32(
			inst.pos,
			linalg.QUATERNIONF32_IDENTITY,
			{0.5, 0.5, 0.5},
		),
		params = levi.Material_Params{base_color = inst.color, emissive = {0, 0, 0, 0}},
	}
}

opaque_pass :: proc(ctx: ^levi.Render_Context) {
	r := ctx.renderer
	if len(r.instances) == 0 do return

	// Bind shaders from the first instance's material
	mat_id := r.instances[0].material_id
	mat := r.materials[mat_id]
	gpu.cmd_set_shaders(ctx.cmd_buf, r.shaders[mat.vert], r.shaders[mat.frag])

	root := gpu.arena_alloc(ctx.frame_arena, levi.Vertex_Root)
	for attr in levi.Vertex_Attribute {
		if attr == .COUNT do continue
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

main :: proc() {
	logger := log.create_console_logger(.Info)
	context.logger = logger
	defer log.destroy_console_logger(logger)

	ok := sdl.Init({.VIDEO})
	ensure(ok, "sdl is not initialized"); log.info("sdl initialized")
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Levi Viewer",
		1280,
		720,
		{.VULKAN, .RESIZABLE, .HIGH_PIXEL_DENSITY},
	)
	ensure(window != nil, "Window creation failed"); log.info("sdl window initialized")
	defer sdl.DestroyWindow(window)

	eng := levi.engine_init(window, 1280, 720)
	defer levi.engine_destroy(eng)

	app: App_State
	app.vert = levi.create_shader(eng, #load("../samples/triangle/unlit.vert.spv", []u32), .Vertex)
	app.frag = levi.create_shader(
		eng,
		#load("../samples/triangle/unlit.frag.spv", []u32),
		.Fragment,
	)
	app.mat = levi.create_material(
		eng,
		app.vert,
		app.frag,
		params_size = size_of(levi.Material_Params),
	)
	mesh := levi.create_mesh(eng, levi.generate_quad_mesh())

	{
		levi.spawn_instance(eng, mesh, app.mat)
		append(&app.instances, My_Instance{pos = {-1, 0, 0}, color = {1, 0, 0, 1}})

		levi.spawn_instance(eng, mesh, app.mat)
		append(&app.instances, My_Instance{pos = {1, 0, 0}, color = {0, 1, 0, 1}})
	}

	eng.extract = extract
	eng.user_data = &app
	append(&eng.passes, opaque_pass)

	frame_data: levi.Frame_Data

	for {
		if !poll_window_events(window) do break

		for &inst in app.instances {
			inst.pos[1] += 0.001
			if inst.pos[1] > 1 do inst.pos[1] = -1
		}

		aspect := f32(eng.win_s[0]) / f32(eng.win_s[1])
		view := linalg.matrix4_look_at_f32({0, 0, -3}, {0, 0, 0}, {0, 1, 0})
		proj := linalg.matrix4_perspective_f32(linalg.to_radians(f32(45.0)), aspect, 0.1, 100.0)
		frame_data.view_proj = proj * view

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
