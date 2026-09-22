package main

import "../src/gpu/gpu"


opaque_pass :: proc(
	cmd: gpu.Command_Buffer,
	target: gpu.Texture,
	arena: ^gpu.Arena,
	shaders: Shader_Pair,
) {

	gpu.cmd_set_shaders(cmd, shaders[.Vertex], shaders[.Fragment])

	gpu.cmd_begin_render_pass(
		cmd,
		{color_attachments = {{texture = target, clear_color = {0.7, 0.7, 0.7, 1.0}}}},
	)

	Vert_Data :: struct #all_or_none {
		pos: rawptr,
		col: rawptr,
	}

	verts := gpu.arena_alloc(arena, Vert_Data)

	gpu.cmd_draw_indexed_raw(cmd, verts, gpu.null, m[.IDX], .U32, scene.index_count)
	gpu.cmd_end_render_pass(cmd)
}
