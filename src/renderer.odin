package renderer

import "gpu/gpu"

FLIGHT :: 3

// In renderer.odin or shared.odin
Scene_Data :: struct {
	view_proj: [16]f32,
	positions: rawptr,
	normals:   rawptr,
	uvs:       rawptr,
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


Attribute_Type :: enum {
	COLOR,
	NORMAL,
	UV,
}

STRIDES := #partial [Attribute_Type]int {
	.COLOR  = size_of([4]f32),
	.NORMAL = size_of([3]f32),
	.UV     = size_of([2]f32),
}

Renderer :: struct {
	positions:      gpu.slice_t([3]f32),
	indices:        gpu.slice_t(u32),
	attributes:     [Attribute_Type]gpu.slice_t(u8),
	gpu_positions:  gpu.slice_t([3]f32),
	gpu_indices:    gpu.slice_t(u32),
	gpu_attributes: [Attribute_Type]gpu.slice_t(u8),
}

upload_geometry :: proc(renderer: ^Renderer) {
	pos_count := i32(len(renderer.positions.cpu))
	idx_count := i32(len(renderer.indices.cpu))

	renderer.gpu_positions = gpu.mem_alloc([3]f32, pos_count, gpu.Memory.GPU)
	renderer.gpu_indices = gpu.mem_alloc(u32, idx_count, gpu.Memory.GPU)

	upload_cmd := gpu.commands_begin(.Main)
	gpu.cmd_mem_copy(upload_cmd, renderer.gpu_positions, renderer.positions)
	gpu.cmd_mem_copy(upload_cmd, renderer.gpu_indices, renderer.indices)

	for t in Attribute_Type {
		attr_count := i32(len(renderer.attributes[t].cpu))
		if attr_count > 0 {
			renderer.gpu_attributes[t] = gpu.mem_alloc(u8, attr_count, gpu.Memory.GPU)
			gpu.cmd_mem_copy(upload_cmd, renderer.gpu_attributes[t], renderer.attributes[t])
		}
	}

	gpu.cmd_barrier(upload_cmd, .Transfer, .All, {})
	gpu.queue_submit(.Main, {upload_cmd})
	gpu.wait_idle()
}
