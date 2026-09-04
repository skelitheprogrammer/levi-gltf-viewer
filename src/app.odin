package main

import "../src/gpu/gpu"
import levi "../src/levi"
import "base:intrinsics"
import "core:mem"

make_f32_array :: #force_inline proc($N: int, $val: f32) -> (res: [N]f32) {
	for i in 0 ..< N do res[i] = val
	return
}

Custom_Material :: struct {
	color: [4]f32,
	time:  f32,
}

App_State :: struct {
	mat_type:  levi.Material_Type_ID,
	red_mat:   levi.Material_Handle,
	cam:       Camera,
	cam_state: Camera_State,
	time:      f32,
}
extract_view :: proc(user_data: rawptr) -> levi.Frame_Data {
	app := cast(^App_State)(user_data)
	view_proj := get_view_proj(app.cam, app.cam_state.pos, app.cam_state.rot)
	return levi.Frame_Data{view_proj = intrinsics.matrix_flatten(view_proj)}
}
create_quad :: proc(eng: ^levi.Engine) -> levi.Mesh_ID {
	pos := make([][4]f32, 4)
	pos[0] = {-0.5, -0.5, 0, 1}
	pos[1] = {0.5, -0.5, 0, 1}
	pos[2] = {0.5, 0.5, 0, 1}
	pos[3] = {-0.5, 0.5, 0, 1}

	col_arr := make([][4]f32, 4)
	for i in 0 ..< 4 do col_arr[i] = {1, 1, 1, 1}

	idx := make([]u32, 6)
	idx[0] = 0; idx[1] = 1; idx[2] = 2
	idx[3] = 0; idx[4] = 2; idx[5] = 3

	pos_desc := levi.Vertex_Attribute_Desc {
		format          = .Float32,
		component_count = 4,
		offset          = 0,
		stride          = 16,
		normalized      = false,
	}

	col_desc := levi.Vertex_Attribute_Desc {
		format          = .Float32,
		component_count = 4,
		offset          = 0,
		stride          = 16,
		normalized      = false,
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

	w := f32(ctx.win_s[0])
	h := f32(ctx.win_s[1])

	// 1. Viewport and Scissor (Resolves VK_DYNAMIC_STATE_VIEWPORT_WITH_COUNT & SCISSOR_WITH_COUNT)
	gpu.cmd_set_viewport(ctx.cmd_buf, gpu.Viewport{{0, 0}, {w, h}, 0, 1})
	gpu.cmd_set_scissor(ctx.cmd_buf, gpu.Rect_2D{{0, 0}, {u32(w), u32(h)}})

	// 2. Depth State (Resolves VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE, STENCIL, BIAS, etc.)
	// We don't have a depth buffer attached in this basic pass, so we disable depth testing.
	gpu.cmd_set_depth_state(ctx.cmd_buf, gpu.Depth_State{mode = {}, compare = .Always})

	// 3. Blend State (Ensures blending dynamic states are initialized)
	gpu.cmd_set_blend_state(ctx.cmd_buf, gpu.Blend_State{})

	// 4. Raster State (Resolves POLYGON_MODE, FRONT_FACE, CULL_MODE, etc.)
	gpu.cmd_set_raster_state(
		ctx.cmd_buf,
		gpu.Raster_State{topology = .Triangle_List, cull_mode = .Cull_CW},
	)

	// Issue the draw call
	levi.draw_material_type(ctx, app.mat_type)
}
