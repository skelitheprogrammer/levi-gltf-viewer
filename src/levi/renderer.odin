package levi

import "../gpu/gpu"

FLIGHT: u64 : 3


Frame_Data :: struct #align (16) {
	view_proj: matrix[4, 4]f32,
}

Pending_Upload :: struct {
	arena:       gpu.Arena,
	ready_value: u64,
}

Render_State :: struct {
	frame_arenas:      [FLIGHT]gpu.Arena,
	arena_done:        [FLIGHT]u64,
	frame_sem:         gpu.Semaphore,
	next_frame:        u64,
	frame_data_blocks: [FLIGHT]gpu.ptr_t(Frame_Data),
	pending_uploads:   [dynamic]Pending_Upload,
	next_upload_value: u64,
}

render_init :: proc(state: ^Render_State) {
	for &arena in state.frame_arenas {
		arena = gpu.arena_create()
	}

	for &block in state.frame_data_blocks {
		block = gpu.mem_alloc_ptr(Frame_Data, mem_type = .Default)
	}

	state.frame_sem = gpu.semaphore_create()
	state.next_frame = 1
	state.arena_done = {}

	state.pending_uploads = {}
	state.next_upload_value = 1
}

render_destroy :: proc(state: ^Render_State) {
	gpu.wait_idle()

	for &arena in state.frame_arenas {
		gpu.arena_destroy(&arena)
	}
	for block in state.frame_data_blocks {
		gpu.mem_free_ptr(block)
	}

	for &upload in state.pending_uploads {
		gpu.arena_destroy(&upload.arena)
	}
	delete(state.pending_uploads)

	gpu.semaphore_destroy(state.frame_sem)
	state^ = {}
}

acquire_frame_arena :: proc(state: ^Render_State, frame_idx: int) -> ^gpu.Arena {
	if state.arena_done[frame_idx] > 0 {
		gpu.semaphore_wait(state.frame_sem, state.arena_done[frame_idx])
	}
	arena := &state.frame_arenas[frame_idx]
	gpu.arena_free_all(arena)
	return arena
}

render_geometry :: proc(
	state: ^Render_State,
	vertex_data: gpu.gpuptr,
	geom: ^Geometry,
	swapchain: gpu.Texture,
	shaders: Shader_Pair,
	cmd: gpu.Command_Buffer,
) {
	if geom.vertex_count == 0 do return

	if geom.ready_value != 0 {
		gpu.cmd_add_wait_semaphore(cmd, state.frame_sem, geom.ready_value)
	}

	gpu.cmd_begin_render_pass(
		cmd,
		{
			color_attachments = {
				{texture = swapchain, load_op = .Clear, clear_color = {0.1, 0.1, 0.1, 1.0}},
			},
		},
	)

	gpu.cmd_set_raster_state(cmd, gpu.Raster_State{cull_mode = .Cull_CCW})
	gpu.cmd_set_shaders(cmd, shaders[.Vertex], shaders[.Fragment])

	if geom.index_count > 0 && geom.indices.ptr != nil {
		gpu.cmd_draw_indexed_raw(
			cmd,
			vertex_data,
			gpu.null,
			geom.indices,
			geom.index_format,
			geom.index_count,
		)
	} else {
		gpu.cmd_draw(cmd, vertex_data, gpu.null, geom.vertex_count)
	}

	gpu.cmd_end_render_pass(cmd)
}
