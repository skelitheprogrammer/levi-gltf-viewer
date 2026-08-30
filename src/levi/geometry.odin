package levi

import "../gpu/gpu"
import "core:mem"

GPU :: gpu.Memory.GPU

Vertex_Attribute :: enum {
	Position,
	Color,
}

Vertex_Attribute_Sizes := [Vertex_Attribute]i64 {
	.Position = size_of([4]f32),
	.Color    = size_of([4]f32),
}

Geometry_Pool :: struct {
	pools:   [Vertex_Attribute]gpu.ptr,
	offsets: [Vertex_Attribute]i64,
}

Geometry_Stream :: struct {
	data:  rawptr,
	count: i64,
}

geometry_pool_init :: proc(geometry: ^Geometry_Pool, counts: [Vertex_Attribute]i64) {
	for &pool, type in geometry.pools {
		pool = gpu.mem_alloc_raw(Vertex_Attribute_Sizes[type], counts[type], 16, GPU)
	}
}

Geometry_Staging :: struct {
	pool:         ^Geometry_Pool,
	cmd:          gpu.Command_Buffer,
	upload_arena: gpu.Arena,
}

geometry_begin_upload :: proc(pool: ^Geometry_Pool) -> Geometry_Staging {
	return Geometry_Staging {
		pool = pool,
		cmd = gpu.commands_begin(.Transfer),
		upload_arena = gpu.arena_create(),
	}
}

geometry_append :: proc(
	staging: ^Geometry_Staging,
	data: [Vertex_Attribute]Maybe(Geometry_Stream),
) -> (
	result: [Vertex_Attribute]gpu.gpuptr,
) {

	for stream, type in data {
		if stream == nil do continue
		s := stream.?

		elem_size := Vertex_Attribute_Sizes[type]
		bytes := elem_size * s.count
		off_bytes := staging.pool.offsets[type]

		dst := gpu.mem_suballoc(
			staging.pool.pools[type],
			off_bytes / elem_size,
			elem_size,
			s.count,
		)

		st := gpu.arena_alloc_raw(&staging.upload_arena, elem_size, s.count, 16)
		mem.copy(st.cpu, s.data, int(bytes))

		gpu.cmd_mem_copy_raw(staging.cmd, dst.gpu, st.gpu, bytes)

		staging.pool.offsets[type] += bytes
		result[type] = dst.gpu
	}

	return result
}

geometry_submit :: proc(staging: ^Geometry_Staging) {
	gpu.cmd_barrier(staging.cmd, .Transfer, .All, {})
	gpu.queue_submit(.Transfer, {staging.cmd})

	gpu.queue_wait_idle(.Transfer)

	gpu.arena_destroy(&staging.upload_arena)
}
