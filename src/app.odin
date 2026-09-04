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

App_State :: struct {
	mat_type:  levi.Material_Type_ID,
	red_mat:   levi.Material_Handle,
	time:      f32,
	cam:       Camera,
	cam_state: Camera_State,
}

extract_view :: proc(user_data: rawptr) -> levi.Frame_Data {
	app := cast(^App_State)(user_data)
	view_proj := get_view_proj(app.cam, app.cam_state.pos, app.cam_state.rot)
	return levi.Frame_Data{view_proj = intrinsics.matrix_flatten(view_proj)}
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

	// 1. Begin Render Pass (Automatically sets Viewport, Scissor, and all required dynamic states!)
	gpu.cmd_begin_render_pass(
		ctx.cmd_buf,
		{color_attachments = {{texture = ctx.target, clear_color = {0.15, 0.15, 0.15, 1.0}}}},
	)

	// 2. Set Depth State (No depth buffer attached, so disable depth testing)
	gpu.cmd_set_depth_state(ctx.cmd_buf, gpu.Depth_State{mode = {}, compare = .Always})

	// 3. Set Blend State
	gpu.cmd_set_blend_state(ctx.cmd_buf, gpu.Blend_State{})

	// 4. Set Raster State (Overrides defaults set by begin_render_pass)
	gpu.cmd_set_raster_state(
		ctx.cmd_buf,
		gpu.Raster_State{topology = .Triangle_List, cull_mode = .Cull_CW},
	)

	// 5. Draw
	levi.draw_material_type(ctx, app.mat_type)

	// 6. End Render Pass
	gpu.cmd_end_render_pass(ctx.cmd_buf)
}
