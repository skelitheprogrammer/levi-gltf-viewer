package main

import "../src/gpu/gpu"

FLIGHT :: 3

Renderer :: struct {
	arenas: [FLIGHT]gpu.Arena,
	sem:    gpu.Semaphore,
	next:   u64,
	size:   [2]u32,
}

renderer_init :: proc(r: ^Renderer, size: [2]u32) {
	for &a in r.arenas do a = gpu.arena_create()
	r.sem = gpu.semaphore_create(0)
	r.next = 1
	r.size = size
}

renderer_destroy :: proc(r: ^Renderer) {
	for &a in r.arenas do gpu.arena_destroy(&a)
	gpu.semaphore_destroy(r.sem)
}

frame_begin :: proc(
	r: ^Renderer,
	win_size: [2]i32,
) -> (
	cmd: gpu.Command_Buffer,
	target: gpu.Texture,
	arena: ^gpu.Arena,
	ok: bool,
) {
	new_size := [2]u32{u32(win_size.x), u32(win_size.y)}
	if r.size != new_size {
		gpu.queue_wait_idle(.Main)
		r.size = new_size
		gpu.swapchain_resize(new_size)
	}

	if r.next > FLIGHT do gpu.semaphore_wait(r.sem, r.next - FLIGHT)

	target = gpu.swapchain_acquire_next()
	if target == {} {
		gpu.queue_wait_idle(.Main)
		gpu.swapchain_resize(r.size)
		return
	}

	arena = &r.arenas[r.next % FLIGHT]
	gpu.arena_free_all(arena)
	cmd = gpu.commands_begin(.Main)
	return cmd, target, arena, true
}

frame_end :: proc(fs: ^Renderer, cmd: gpu.Command_Buffer) {
	gpu.cmd_add_signal_semaphore(cmd, fs.sem, fs.next)
	gpu.queue_submit(.Main, {cmd})
	gpu.swapchain_present(.Main, fs.sem, fs.next)
	fs.next += 1
}
