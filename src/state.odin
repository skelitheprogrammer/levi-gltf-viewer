package levi

import gpu "gpu/gpu"


FLIGHT :: 3

Render_State :: struct {
	upload_arena: gpu.Arena,
	frame_arenas: [FLIGHT]gpu.Arena,
	sem:          gpu.Semaphore,
	frame_index:  u64,
	shader_sys:   Shader_System,
}

render_state_init :: proc(rs: ^Render_State) -> Error_Code {
	if !gpu.init() do return .GPU_Init

	rs.upload_arena = gpu.arena_create()
	for i in 0 ..< FLIGHT {
		rs.frame_arenas[i] = gpu.arena_create()
	}

	rs.sem = gpu.semaphore_create(0)
	rs.frame_index = 0

	shader_system_init(&rs.shader_sys, "shaders")

	return .None
}

render_state_destroy :: proc(rs: ^Render_State) {
	gpu.wait_idle()

	shader_system_destroy(&rs.shader_sys)
	gpu.semaphore_destroy(rs.sem)
	gpu.arena_destroy(&rs.upload_arena)
	for i in 0 ..< FLIGHT {
		gpu.arena_destroy(&rs.frame_arenas[i])
	}

	gpu.cleanup()
	rs^ = {}
}

render_state_flight_index :: proc(rs: ^Render_State) -> int {
	return int(rs.frame_index % FLIGHT)
}

render_state_frame_arena :: proc(rs: ^Render_State) -> ^gpu.Arena {
	return &rs.frame_arenas[render_state_flight_index(rs)]
}
