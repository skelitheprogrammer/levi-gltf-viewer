package levi

import "../gpu/gpu"
import "core:mem"

Vertex_Attribute :: enum {
	COLOR,
}


Draw_Data :: struct #align (16) {
	frame_data:    rawptr,
	instance_data: rawptr,
	position:      rawptr,
	attributes:    [Vertex_Attribute]rawptr,
}

Geometry_Stream :: struct {
	data:   rawptr,
	count:  int,
	stride: int,
}

Geometry_Desc :: struct {
	positions:    Geometry_Stream,
	attributes:   [Vertex_Attribute]Geometry_Stream,
	indices:      Geometry_Stream,
	index_format: gpu.Index_Format,
}

Geometry :: struct {
	position:     gpu.gpuptr,
	attributes:   [Vertex_Attribute]gpu.gpuptr,
	indices:      gpu.gpuptr,
	vertex_count: u32,
	index_count:  u32,
	index_format: gpu.Index_Format,
	ready_value:  u64,
}

upload_geometry :: proc {
	upload_geometry_blocking,
	upload_geometry_deferred,
}

upload_geometry_blocking :: proc(state: ^Render_State, desc: Geometry_Desc) -> Geometry {
	geom, arena, cmd, ok := upload_geometry_data(desc)

	if !ok {
		return geom
	}

	gpu.queue_submit(.Transfer, {cmd})

	gpu.queue_wait_idle(.Transfer)

	gpu.arena_destroy(&arena)

	return geom
}

upload_geometry_deferred :: proc(
	state: ^Render_State,
	desc: Geometry_Desc,
	out_ready_value: ^u64,
) -> Geometry {
	geom, arena, cmd, ok := upload_geometry_data(desc)

	if !ok {
		out_ready_value^ = 0
		return geom
	}

	ready_value := state.next_upload_value
	state.next_upload_value += 1

	gpu.cmd_add_signal_semaphore(cmd, state.frame_sem, ready_value)

	gpu.queue_submit(.Transfer, {cmd})

	append(&state.pending_uploads, Pending_Upload{arena = arena, ready_value = ready_value})

	geom.ready_value = ready_value

	out_ready_value^ = ready_value

	return geom
}

@(private)
upload_geometry_data :: #force_inline proc(
	desc: Geometry_Desc,
) -> (
	geom: Geometry,
	arena: gpu.Arena,
	cmd: gpu.Command_Buffer,
	ok: bool,
) {
	vertex_count := desc.positions.count
	index_count := desc.indices.count

	has_positions := vertex_count > 0 && desc.positions.data != nil

	has_indices := index_count > 0 && desc.indices.data != nil

	geom.vertex_count = u32(vertex_count)
	geom.index_count = u32(index_count)
	geom.index_format = desc.index_format

	if !has_positions {
		return
	}

	arena = gpu.arena_create()

	pos_mem := gpu.mem_alloc_raw(desc.positions.stride, vertex_count, 16, mem_type = .GPU)

	geom.position = pos_mem.gpu

	cmd = gpu.commands_begin(.Transfer)

	st_pos := gpu.arena_alloc_raw(&arena, desc.positions.stride, vertex_count, 16)

	mem.copy(st_pos.cpu, desc.positions.data, desc.positions.stride * vertex_count)

	gpu.cmd_mem_copy_raw(cmd, pos_mem.gpu, st_pos.gpu, desc.positions.stride * vertex_count)

	for attr in Vertex_Attribute {
		stream := desc.attributes[attr]

		if stream.count > 0 && stream.data != nil {
			attr_mem := gpu.mem_alloc_raw(stream.stride, stream.count, 16, mem_type = .GPU)

			st_attr := gpu.arena_alloc_raw(&arena, stream.stride, stream.count, 16)

			mem.copy(st_attr.cpu, stream.data, stream.stride * stream.count)

			gpu.cmd_mem_copy_raw(cmd, attr_mem.gpu, st_attr.gpu, stream.stride * stream.count)

			geom.attributes[attr] = attr_mem.gpu
		} else {
			geom.attributes[attr] = gpu.null
		}
	}

	if has_indices {
		index_mem := gpu.mem_alloc_raw(desc.indices.stride, index_count, 16, mem_type = .GPU)

		st_idx := gpu.arena_alloc_raw(&arena, desc.indices.stride, index_count, 16)

		mem.copy(st_idx.cpu, desc.indices.data, desc.indices.stride * index_count)

		gpu.cmd_mem_copy_raw(cmd, index_mem.gpu, st_idx.gpu, desc.indices.stride * index_count)

		geom.indices = index_mem.gpu
	} else {
		geom.indices = gpu.null
	}

	gpu.cmd_barrier(cmd, .Transfer, .All)

	ok = true

	return
}

geometry_destroy :: proc(geom: ^Geometry) {
	if geom.position.ptr != nil {
		gpu.mem_free_raw(geom.position)

		geom.position = gpu.null
	}

	for attr in Vertex_Attribute {
		if geom.attributes[attr].ptr != nil {
			gpu.mem_free_raw(geom.attributes[attr])

			geom.attributes[attr] = gpu.null
		}
	}

	if geom.indices.ptr != nil {
		gpu.mem_free_raw(geom.indices)

		geom.indices = gpu.null
	}

	geom^ = {}
}

pump_uploads :: proc(state: ^Render_State) {
	if len(state.pending_uploads) == 0 {
		return
	}

	current := gpu.semaphore_get_value(state.frame_sem)

	write_idx := 0

	for &upload in state.pending_uploads {
		if current >= upload.ready_value {
			gpu.arena_destroy(&upload.arena)
		} else {
			state.pending_uploads[write_idx] = upload

			write_idx += 1
		}
	}

	resize(&state.pending_uploads, write_idx)
}

flush_uploads :: proc(state: ^Render_State) {
	if len(state.pending_uploads) == 0 {
		return
	}

	last_value := state.pending_uploads[len(state.pending_uploads) - 1].ready_value

	gpu.semaphore_wait(state.frame_sem, last_value)

	for &upload in state.pending_uploads {
		gpu.arena_destroy(&upload.arena)
	}

	clear(&state.pending_uploads)
}
