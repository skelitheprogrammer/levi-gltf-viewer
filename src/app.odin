package main

import "../src/gpu/gpu"
import levi "../src/levi"
import "base:intrinsics"
import "core:math/linalg"
import "core:mem"

Custom_Material :: struct {
	color: [4]f32,
	time:  f32,
}

My_Instance :: struct {
	pos:   [3]f32,
	rot:   linalg.Quaternionf32,
	scale: [3]f32,
}

App_State :: struct {
	instances: [dynamic]My_Instance,
	mat_type:  levi.Material_Type_ID,
	red_mat:   levi.Material_Handle,
	time:      f32,
	cam:       Camera,
	cam_state: Camera_State,
}

extract_view :: proc(user_data: rawptr) -> levi.Frame_Data {
	app := cast(^App_State)(user_data)
	aspect := f32(app.cam.aspect)

	forward := linalg.mul(app.cam_state.rot, [3]f32{0, 0, 1})
	target := app.cam_state.pos + forward

	view := linalg.matrix4_look_at_f32(app.cam_state.pos, target, [3]f32{0, 1, 0})
	proj := linalg.matrix4_perspective_f32(linalg.to_radians(f32(60.0)), aspect, 0.1, 100.0)

	return levi.Frame_Data{view_proj = intrinsics.matrix_flatten(proj * view)}
}

extract_instance :: proc(id: levi.Instance_ID, user_data: rawptr) -> [16]f32 {
	app := cast(^App_State)(user_data)
	inst := app.instances[id]
	mat := linalg.matrix4_from_trs_f32(inst.pos, inst.rot, inst.scale)
	return intrinsics.matrix_flatten(mat)
}
create_quad :: proc(eng: ^levi.Engine) -> levi.Mesh_ID {
	pos := make([][4]f32, 4)
	pos[0] = {-0.5, -0.5, 0, 1}; pos[1] = {0.5, -0.5, 0, 1}
	pos[2] = {0.5, 0.5, 0, 1}; pos[3] = {-0.5, 0.5, 0, 1}

	col_arr := make([][4]f32, 4)
	for i in 0 ..< 4 do col_arr[i] = {1, 1, 1, 1}

	idx := make([]u32, 6)
	idx[0] = 0; idx[1] = 1; idx[2] = 2
	idx[3] = 0; idx[4] = 2; idx[5] = 3

	pos_desc := levi.Vertex_Attribute_Desc {
		format          = .Float32,
		component_count = 4,
		stride          = 16,
	}
	col_desc := levi.Vertex_Attribute_Desc {
		format          = .Float32,
		component_count = 4,
		stride          = 16,
	}

	mesh_id, _ := levi.create_mesh(
		eng,
		&levi.Mesh_Desc {
			attributes = #partial{
				.Position = mem.slice_to_bytes(pos[:]),
				.Color = mem.slice_to_bytes(col_arr[:]),
			},
			attribute_descs = #partial{.Position = pos_desc, .Color = col_desc},
			indices = idx,
		},
	)
	return mesh_id
}

my_opaque_pass :: proc(ctx: ^levi.Render_Context) {
	app := cast(^App_State)(ctx.user_data)
	if app == nil do return

	gpu.cmd_begin_render_pass(
		ctx.cmd_buf,
		{color_attachments = {{texture = ctx.target, clear_color = {0.15, 0.15, 0.15, 1.0}}}},
	)

	gpu.cmd_set_raster_state(
		ctx.cmd_buf,
		gpu.Raster_State{topology = .Triangle_List, cull_mode = .None},
	)

	levi.draw_material_type(ctx, app.mat_type)

	gpu.cmd_end_render_pass(ctx.cmd_buf)
}
