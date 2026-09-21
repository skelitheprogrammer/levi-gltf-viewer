package main

import "../src/gpu/gpu"

GPU :: gpu.Memory.GPU
FLIGHT :: 3

Frame_State :: struct {
	arenas: [FLIGHT]gpu.Arena,
	sem:    gpu.Semaphore,
	next:   u64,
	size:   [2]u32,
}

frame_init :: proc(fs: ^Frame_State, size: [2]u32) {
	for &a in fs.arenas do a = gpu.arena_create()
	fs.sem = gpu.semaphore_create(0)
	fs.next = 1
	fs.size = size
}

frame_destroy :: proc(fs: ^Frame_State) {
	for &a in fs.arenas do gpu.arena_destroy(&a)
	gpu.semaphore_destroy(fs.sem)
}

frame_begin :: proc(
	fs: ^Frame_State,
	win_size: [2]i32,
) -> (
	cmd: gpu.Command_Buffer,
	target: gpu.Texture,
	arena: ^gpu.Arena,
	ok: bool,
) {
	new_size := [2]u32{u32(win_size.x), u32(win_size.y)}
	if fs.size != new_size {
		gpu.queue_wait_idle(.Main)
		fs.size = new_size
		gpu.swapchain_resize(new_size)
	}

	if fs.next > FLIGHT do gpu.semaphore_wait(fs.sem, fs.next - FLIGHT)

	target = gpu.swapchain_acquire_next()
	if target == {} {
		gpu.queue_wait_idle(.Main)
		gpu.swapchain_resize(fs.size)
		return
	}

	arena = &fs.arenas[fs.next % FLIGHT]
	gpu.arena_free_all(arena)
	cmd = gpu.commands_begin(.Main)
	return cmd, target, arena, true
}

frame_end :: proc(fs: ^Frame_State, cmd: gpu.Command_Buffer) {
	gpu.cmd_add_signal_semaphore(cmd, fs.sem, fs.next)
	gpu.queue_submit(.Main, {cmd})
	gpu.swapchain_present(.Main, fs.sem, fs.next)
	fs.next += 1
}
