package levi

import "../gpu/gpu"

FLIGHT: u64 : 3

Render_State :: struct {
	frame_arenas: [FLIGHT]gpu.Arena,
	frame_sem:    gpu.Semaphore,
	next_frame:   u64,
}

Draw :: struct {
	mesh:  u32,
	model: matrix[4, 4]f32,
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
