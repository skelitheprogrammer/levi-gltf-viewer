package main

import "../src/gpu/gpu"

Buffers :: struct {
	vertex:    gpu.ptr,
	indices:   gpu.ptr,
	vert_used: u64,
	idx_used:  u64,
	capacity:  u64,
	meshes:    [dynamic]Mesh,
}

Mesh :: struct {
	vert_offset: u32,
	idx_offset:  u32,
	vert_count:  u32,
	idx_count:   u32,
}

buffers_init :: proc(b: ^Buffers, capacity: u64) {
	b.vertex = gpu.mem_alloc_raw(1, capacity, 16, .GPU)
	b.indices = gpu.mem_alloc_raw(1, capacity, 4, .GPU)
	b.capacity = capacity
}
