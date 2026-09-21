package main

import "../src/gpu/gpu"
import "base:runtime"
GPU_Stream :: enum {
	POS,
	COL,
	UVS,
	IDX,
}

GPU_Stream_Sizes :: [GPU_Stream]i64 {
	.POS = size_of([4]f32),
	.COL = size_of([4]f32),
	.UVS = size_of([2]f32),
	.IDX = size_of(u32),
}

Stream :: struct {
	using slice: runtime.Raw_Slice,
	size:        i64,
	align:       i64,
}

Mesh :: distinct [GPU_Stream]Stream
Mesh_GPU :: distinct [GPU_Stream]gpu.gpuptr

mesh_upload :: proc(arena: ^gpu.Arena, cmd: gpu.Command_Buffer, mesh: Mesh) -> Mesh_GPU {
	out: Mesh_GPU
	for type in GPU_Stream {
		s := mesh[type]
		if s.len == 0 do continue
		staging := gpu.arena_alloc_raw(arena, s.size, s.len, s.align)
		staging.cpu = s.data
		out[type] = gpu.mem_alloc_raw(s.size, s.len, s.align, GPU)
		gpu.cmd_mem_copy_raw(cmd, out[type], staging, s.size * i64(s.len))
	}
	return out
}

mesh_destroy :: proc(mesh: ^Mesh_GPU) {
	for type in GPU_Stream {
		if mesh[type] != gpu.null do gpu.mem_free_raw(mesh[type])
	}
	mesh^ = {}
}
