package main

import "../src/gpu/gpu"
import "base:intrinsics"

Buffer_Desc :: struct {
	size, count, align, bytes: i64,
}

Staging_Entry :: struct($T: typeid) where intrinsics.type_is_enum(T) {
	ptr:  gpu.ptr,
	desc: Buffer_Desc,
	type: T,
}

upload_data :: proc(
	arena: ^gpu.Arena,
	data: []u8,
	desc: Buffer_Desc,
	$T: typeid,
) -> Staging_Entry(T) where intrinsics.type_is_enum(T) {
	return {
		ptr = gpu.arena_alloc_raw(arena, desc.size, desc.count, desc.align),
		desc = desc,
		type = T,
	}
}

handle_staging :: proc(
	entries: [dynamic]Staging_Entry($T),
	pools: ^Pool_State(T),
) where intrinsics.type_is_enum(T) {
	if entries == nil || len(entries) == 0 do return

	cmd := gpu.commands_begin(.Transfer)

	for entry in entries {
		gpu.cmd_mem_copy_raw(cmd, pools.pools[entry.type], entry.ptr.gpu, bytes)
	}

	gpu.cmd_barrier(cmd, .Transfer, .All)
	gpu.queue_submit(.Main, {cmd})
}
