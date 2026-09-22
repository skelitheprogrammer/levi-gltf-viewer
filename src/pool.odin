package main

import "../src/gpu/gpu"
import "base:intrinsics"

Pool_State :: struct($T: typeid) where intrinsics.type_is_enum(T) {
	pools: [T]gpu.gpuptr,
}

pool_init :: proc(
	p: ^Pool_State($T),
	sizes: [T]i64,
	counts: [T]i64,
	aligns: [T]i64,
	types: [T]gpu.Memory,
	allocator := context.allocator,
) {
	for t in T {
		p.pools[t] = gpu.mem_alloc_raw(sizes[t], counts[t], aligns[t], types[t])
	}
}
