package renderer

import "gpu/gpu"

GPU :: gpu.Memory.GPU
FLIGHT :: 3

Attribute_Semantic :: enum {
	POSITION,
	NORMAL,
	UV,
	COLOR,
}

Geometry :: struct {
	attributes: [Attribute_Semantic]gpu.slice_t(u8),
	indices:    gpu.slice_t(u32),
	draws:      gpu.slice_t(gpu.Draw_Indexed_Indirect_Command),
}

Renderer :: struct {
	geometry:   Geometry,
	models:     gpu.slice_t([16]f32),
	draw_count: gpu.ptr_t(u32),
}

Scene_Data :: struct {
	view_proj:  [16]f32,
	models:     rawptr,
	attributes: [Attribute_Semantic]rawptr,
}

Frag_Data :: struct {
	base_color: [4]f32,
}

Render_State :: struct {
	frame_arenas: [FLIGHT]gpu.Arena,
	frame_sem:    gpu.Semaphore,
}

init :: proc(state: ^Render_State) {
	for &f in state.frame_arenas do f = gpu.arena_create()
	state.frame_sem = gpu.semaphore_create()
}

destroy :: proc(state: ^Render_State) {
	gpu.wait_idle()
	for &f in state.frame_arenas do gpu.arena_destroy(&f)
	gpu.semaphore_destroy(state.frame_sem)
}

upload_slice :: proc(cmd: gpu.Command_Buffer, s: ^gpu.slice_t($T)) {
	if len(s.cpu) == 0 {return}
	staging := s^
	s^ = gpu.mem_alloc_slice(T, len(s.cpu), GPU)
	gpu.cmd_mem_copy(cmd, s^, staging)
}

upload_ptr :: proc(cmd: gpu.Command_Buffer, p: ^gpu.ptr_t($T)) {
	staging := p^
	p^ = gpu.mem_alloc_ptr(T, GPU)
	if staging.cpu != nil {
		gpu.cmd_mem_copy(cmd, p^, staging)
	}
}

upload_geometry :: proc(r: ^Renderer) {
	cmd := gpu.commands_begin(.Main)
	for &a in r.geometry.attributes do upload_slice(cmd, &a)
	upload_slice(cmd, &r.geometry.indices)
	upload_slice(cmd, &r.geometry.draws)
	upload_slice(cmd, &r.models)
	upload_ptr(cmd, &r.draw_count)
	gpu.cmd_barrier(cmd, .Transfer, .All, {})
	gpu.queue_submit(.Main, {cmd})
	gpu.wait_idle()
}

free_geometry :: proc(r: ^Renderer) {
	for a in r.geometry.attributes do gpu.mem_free(a)
	gpu.mem_free(r.geometry.indices)
	gpu.mem_free(r.geometry.draws)
	gpu.mem_free(r.models)
	gpu.mem_free(r.draw_count)
	r^ = {}
}
