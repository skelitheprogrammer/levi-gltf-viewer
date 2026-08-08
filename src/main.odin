package main

import gpu "../src/gpu/gpu"
import "core:flags"
import "core:log"
import sdl "vendor:sdl3"

FLIGHT :: 3

Render_State :: struct {
	frames:    [FLIGHT]gpu.Arena,
	semaphore: gpu.Semaphore,
}

Vertex_Attribute :: enum {
	POSITION,
	COLOR,
}

Buffers :: struct {
	attributes: [Vertex_Attribute]gpu.slice_t(u8),
	indices:    gpu.slice_t(u32),
	
}

main :: proc() {
	logger := log.create_console_logger()
	context.logger = logger
	defer log.destroy_console_logger(logger)
	ok: bool

	ok = sdl.Init({.VIDEO}); ensure(ok)
	window := sdl.CreateWindow("test", 800, 600, {.VULKAN, .FULLSCREEN, .RESIZABLE, .BORDERLESS})
	defer {
		sdl.DestroyWindow(window)
	}

	ok = gpu.init(); ensure(ok)
	gpu.swapchain_create_from_sdl(window, FLIGHT, .Mailbox)


	for {
		if poll_events() do break


	}
}

poll_events :: proc() -> (proceed: bool) {
	evt: sdl.Event
	for sdl.PollEvent(&evt) {
		#partial switch evt.type {
		case .KEY_DOWN:
			if evt.key.scancode == .ESCAPE do proceed = false
		case .QUIT:
			proceed = false
		}
	}

	proceed = true
	return
}
