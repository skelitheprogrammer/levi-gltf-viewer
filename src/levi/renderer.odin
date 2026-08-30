package levi

import "../gpu/gpu"

FLIGHT: u64 : 3


Render_State :: struct {
	frame_arenas: [FLIGHT]gpu.Arena,
	frame_sem:    gpu.Semaphore,
	next_frame:   u64,
}

render_init :: proc(state: ^Render_State) {
	for &arena in state.frame_arenas do arena = gpu.arena_create()

	state.frame_sem = gpu.semaphore_create()

	state.next_frame = 1

}

render_destroy :: proc(state: ^Render_State) {
	gpu.wait_idle()

	for &arena in state.frame_arenas do gpu.arena_destroy(&arena)

	gpu.semaphore_destroy(state.frame_sem)

	state^ = {}
}

acquire_frame_arena :: proc(state: ^Render_State, frame_idx: int) -> ^gpu.Arena {
	arena := &state.frame_arenas[frame_idx]
	gpu.arena_free_all(arena)

	return arena
}

draw_call :: proc(
	state: ^Render_State,
	draw_data: gpu.gpuptr,
	geom: ^Geometry,
	swapchain: gpu.Texture,
	shaders: Shader_Pair,
	cmd: gpu.Command_Buffer,
	instance_count: u32,
) {
	if geom.vertex_count == 0 {
		return
	}

	gpu.cmd_begin_render_pass(
		cmd,
		{
			color_attachments = {
				{texture = swapchain, load_op = .Clear, clear_color = {0.1, 0.1, 0.1, 1.0}},
			},
		},
	)

	gpu.cmd_set_raster_state(
		cmd,
		gpu.Raster_State{topology = .Triangle_List, cull_mode = .Cull_CW},
	)

	gpu.cmd_set_shaders(cmd, shaders[.Vertex], shaders[.Fragment])

	gpu.cmd_draw(cmd, draw_data, gpu.null, geom.vertex_count, instance_count)

	gpu.cmd_end_render_pass(cmd)
}
