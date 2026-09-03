package main

import gpu "../src/gpu/gpu"
import levi "../src/levi"
import "base:intrinsics"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import sdl "vendor:sdl3"

My_Instance :: struct {
	pos:   [3]f32,
	color: [4]f32,
}

App_State :: struct {
	instances: [dynamic]My_Instance,
}

Input_State :: struct {
	mouse_dx, mouse_dy: f32,
	keys_pressed:       [dynamic]bool,
}

Camera_State :: struct {
	pos:   [3]f32,
	angle: [2]f32, // x = yaw, y = pitch
	rot:   linalg.Quaternionf32,
}

extract :: proc(id: levi.Instance_ID, user_data: rawptr) -> levi.Extract_Result {
	state := cast(^App_State)user_data
	inst := state.instances[id]
	mat4 := linalg.matrix4_from_trs_f32(inst.pos, linalg.QUATERNIONF32_IDENTITY, {1, 1, 1})
	return levi.Extract_Result {
		transform = transmute([16]f32)mat4,
		params = levi.Material_Params{base_color = inst.color, emissive = {0, 0, 0, 0}},
	}
}

my_opaque_pass :: proc(ctx: ^levi.Render_Context) {
	r := ctx.renderer
	if len(r.instances) == 0 do return

	mat_id := r.instances[0].material_id
	mat := r.materials[mat_id]
	gpu.cmd_set_shaders(ctx.cmd_buf, r.shaders[mat.vert], r.shaders[mat.frag])

	// ENABLED BACK-FACE CULLING: Hides the back of the quads, making them feel like solid 3D objects
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
		root,
		{},
		r.streams[.Indices],
		.U32,
		r.streams[.Indirect_Commands],
		u32(size_of(levi.Indirect_Draw)),
		r.streams[.Draw_Count],
	)

	gpu.cmd_end_render_pass(ctx.cmd_buf)
}

create_quad :: proc(eng: ^levi.Engine) -> levi.Mesh_ID {
	pos := make([][4]f32, 4)
	pos[0] = {-0.5, -0.5, 0, 1}
	pos[1] = {0.5, -0.5, 0, 1}
	pos[2] = {0.5, 0.5, 0, 1}
	pos[3] = {-0.5, 0.5, 0, 1}

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

	_ = sdl.SetWindowRelativeMouseMode(window, true)

	eng := levi.engine_init(window, 1280, 720)
	defer levi.engine_destroy(eng)

	app: App_State
	input: Input_State
	cam_state: Camera_State

	// CAMERA POSITION: Raised Y and pushed back in Z to give a 3D perspective view
	cam_state.pos = {0, 2, 5}

	vert := levi.create_shader(eng, #load("../samples/triangle/unlit.vert.spv", []u32), .Vertex)
	frag := levi.create_shader(eng, #load("../samples/triangle/unlit.frag.spv", []u32), .Fragment)
	mat := levi.create_material(eng, vert, frag, params_size = size_of(levi.Material_Params))
	mesh := create_quad(eng)

	levi.spawn_instance(eng, mesh, mat)
	append(&app.instances, My_Instance{pos = {1, 0, 0}, color = {1, 0, 0, 1}})

	levi.spawn_instance(eng, mesh, mat)
	// OFFSET: Moved green quad back in Z to create depth separation
	append(&app.instances, My_Instance{pos = {-1, 0, -1}, color = {0, 1, 0, 1}})

	eng.extract = extract
	eng.user_data = &app
	append(&eng.passes, my_opaque_pass)

	frame_data: levi.Frame_Data
	cam: Camera = {
		mode   = Perspective{linalg.to_radians(f32(60))},
		near   = 0.1,
		far    = 100.0,
		aspect = f32(eng.win_s[0]) / f32(eng.win_s[1]),
	}

	last_time := sdl.GetPerformanceCounter()
	ts_freq := sdl.GetPerformanceFrequency()

	for {
		if !poll_window_events(window, &input) do break

		now_ts := sdl.GetPerformanceCounter()
		delta_time := min(0.1, f32(f64((now_ts - last_time) * 1000) / f64(ts_freq)) / 1000.0)
		last_time = now_ts

		w, h: i32
		sdl.GetWindowSizeInPixels(window, &w, &h)
		eng.win_s = {w, h}

		if eng.win_s[0] == 0 || eng.win_s[1] == 0 do continue
		cam.aspect = f32(eng.win_s[0]) / f32(eng.win_s[1])

		update_camera(&cam_state, &input, delta_time)
		frame_data.view_proj = intrinsics.matrix_flatten(
			get_view_proj(cam, cam_state.pos, cam_state.rot),
		)

		levi.draw(eng, &frame_data)
	}
}

update_camera :: proc(cam: ^Camera_State, input: ^Input_State, dt: f32) {
	mouse_sensitivity: f32 = 0.002

	// Invert X so mouse right looks right
	cam.angle.x -= input.mouse_dx * mouse_sensitivity
	// Invert Y so mouse down looks down
	cam.angle.y -= input.mouse_dy * mouse_sensitivity

	cam.angle.y = clamp(cam.angle.y, -1.5, 1.5) // ~ -90 to 90 degrees

	move_speed: f32 = 2.0
	move_dir: [3]f32

	is_pressed :: proc(input: ^Input_State, key: sdl.Scancode) -> bool {
		idx := int(key)
		if idx >= len(input.keys_pressed) {
			return false
		}
		return input.keys_pressed[idx]
	}

	if is_pressed(input, .W) do move_dir.z -= 1
	if is_pressed(input, .S) do move_dir.z += 1
	if is_pressed(input, .D) do move_dir.x += 1
	if is_pressed(input, .A) do move_dir.x -= 1
	if is_pressed(input, .E) do move_dir.y += 1
	if is_pressed(input, .Q) do move_dir.y -= 1

	if linalg.dot(move_dir, move_dir) > 0 {
		move_dir = linalg.normalize(move_dir)
	}

	pitch_rot := linalg.quaternion_angle_axis(cam.angle.y, [3]f32{1, 0, 0})
	yaw_rot := linalg.quaternion_angle_axis(cam.angle.x, [3]f32{0, 1, 0})

	// FIXED: yaw_rot * pitch_rot applies pitch locally after yawing, preventing "roll"
	cam.rot = yaw_rot * pitch_rot

	world_move_dir := linalg.mul(cam.rot, move_dir)
	cam.pos += world_move_dir * (move_speed * dt)
}

poll_window_events :: proc(window: ^sdl.Window, input: ^Input_State) -> (proceed: bool) {
	input.mouse_dx = 0
	input.mouse_dy = 0
	evt: sdl.Event
	proceed = true
	for sdl.PollEvent(&evt) {
		#partial switch evt.type {
		case .QUIT:
			proceed = false
		case .KEY_DOWN:
			if evt.key.scancode == .F12 {
				proceed = false
			} else {
				idx := int(evt.key.scancode)
				for len(input.keys_pressed) <= idx {
					append(&input.keys_pressed, false)
				}
				input.keys_pressed[idx] = true
			}
		case .KEY_UP:
			idx := int(evt.key.scancode)
			for len(input.keys_pressed) <= idx {
				append(&input.keys_pressed, false)
			}
			input.keys_pressed[idx] = false
		case .WINDOW_CLOSE_REQUESTED:
			if evt.window.windowID == sdl.GetWindowID(window) do proceed = false
		case .MOUSE_MOTION:
			input.mouse_dx += evt.motion.xrel
			input.mouse_dy += evt.motion.yrel
		}
	}
	return
}
