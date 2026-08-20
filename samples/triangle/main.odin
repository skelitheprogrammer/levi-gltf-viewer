// samples/triangle/main.odin
package main

import renderer "../../src/"
import "../../src/gpu/gpu"
import "core:fmt"
import "core:log"
import "core:math"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import sdl "vendor:sdl3"

App :: struct {
	window:        ^sdl.Window,
	model:         renderer.Renderer,
	shaders:       renderer.Shader_Pair,
	render:        renderer.Render_State,
	cam:           renderer.Camera,
	model_path:    string,
	model_loaded:  bool,
	win_w:         i32,
	win_h:         i32,
	staging_arena: gpu.Arena,
	keys:          [512]bool,
	next_frame:    u64,
	quit:          bool,
	path_mutex:    sync.Mutex,
	pending_path:  string,
	has_pending:   bool,
}

init :: proc(app: ^App, window: ^sdl.Window) {
	app.window = window
	sdl.GetWindowSize(window, &app.win_w, &app.win_h)

	ok := gpu.init()
	if !ok {
		log.error("Failed to initialize GPU")
		return
	}
	gpu.swapchain_create_from_sdl(window, renderer.FLIGHT, .Fifo)

	app.staging_arena = gpu.arena_create()

	shader_err: os.Error
	app.shaders, shader_err = renderer.load_shader_pair("unlit.vert.spv", "unlit.frag.spv")
	if shader_err != os.ERROR_NONE {
		log.errorf("Failed to load shaders: %v", shader_err)
	}

	renderer.init(&app.render)

	app.cam = renderer.Camera {
		pos   = {0.0, 0.0, -1.0},
		yaw   = 90.0,
		pitch = 0.0,
	}

	app.next_frame = 1
}

destroy :: proc(app: ^App) {
	gpu.wait_idle()

	if app.model_loaded {
		renderer.free_geometry(&app.model)
	}

	if app.model_path != "" {
		delete(app.model_path)
	}

	gpu.arena_destroy(&app.staging_arena)
	gpu.shader_destroy(app.shaders[.Vertex])
	gpu.shader_destroy(app.shaders[.Fragment])
	renderer.destroy(&app.render)
	gpu.cleanup()
}

load_model :: proc(app: ^App, path: string) {
	if app.model_loaded {
		renderer.free_geometry(&app.model)
		app.model_loaded = false
	}

	if app.model_path != "" {
		delete(app.model_path)
	}

	gpu.arena_free_all(&app.staging_arena)

	res := renderer.load_geometry(path, &app.model, &app.staging_arena)
	if res != nil {
		log.errorf("Failed to load '%s': %v", path, res)
		delete(path)
		return
	}

	renderer.upload_geometry(&app.model)
	gpu.arena_free_all(&app.staging_arena)

	app.model_path = path
	app.model_loaded = true
	log.infof("Loaded: %s", path)
	fmt.printf("> ")
}

stdin_reader :: proc(app: ^App) {
	buf: [4096]byte
	for {
		n, err := os.read(os.stdin, buf[:])
		if err != nil || n <= 0 do break

		path := strings.trim_right(string(buf[:n]), " \t\r\n")
		if len(path) == 0 do continue

		cloned := strings.clone(path)

		sync.mutex_lock(&app.path_mutex)
		if app.pending_path != "" do delete(app.pending_path)
		app.pending_path = cloned
		app.has_pending = true
		sync.mutex_unlock(&app.path_mutex)
	}
}

resolve_path :: proc(app: ^App) -> string {
	sync.mutex_lock(&app.path_mutex)
	if app.has_pending {
		path := app.pending_path
		app.pending_path = ""
		app.has_pending = false
		sync.mutex_unlock(&app.path_mutex)
		return path
	}
	sync.mutex_unlock(&app.path_mutex)

	if !app.model_loaded && len(os.args) > 1 {
		return strings.clone(os.args[1])
	}

	return ""
}

run :: proc(app: ^App) {
	event: sdl.Event
	last_time := sdl.GetTicks()

	thread.run_with_poly_data(app, stdin_reader)

	log.info("Type a model path + Enter to load.")
	if len(os.args) > 1 {
		log.infof("Initial arg: %s", os.args[1])
	} else {
		log.info("Initial arg: (none)")
	}
	fmt.printf("> ")

	for !app.quit {
		now := sdl.GetTicks()
		dt := f32(now - last_time) / 1000.0
		last_time = now

		poll_events(app, &event)

		if path := resolve_path(app); path != "" {
			load_model(app, path)
		}

		update_camera(app, dt)
		render_frame(app)
	}

	os.close(os.stdin)
}

poll_events :: proc(app: ^App, event: ^sdl.Event) {
	for sdl.PollEvent(event) {
		#partial switch event.type {
		case .QUIT:
			app.quit = true
		case .WINDOW_RESIZED:
			app.win_w = event.window.data1
			app.win_h = event.window.data2
			if app.win_w > 0 && app.win_h > 0 {
				gpu.swapchain_resize({u32(app.win_w), u32(app.win_h)})
			}
		case .KEY_DOWN:
			if event.key.scancode == .ESCAPE do app.quit = true
			app.keys[int(event.key.scancode)] = true
		case .KEY_UP:
			app.keys[int(event.key.scancode)] = false
		case .MOUSE_MOTION:
			app.cam.yaw += f32(event.motion.xrel) * 0.15
			app.cam.pitch -= f32(event.motion.yrel) * 0.15
			app.cam.pitch = math.clamp(app.cam.pitch, -89.0, 89.0)
		}
	}
}

update_camera :: proc(app: ^App, dt: f32) {
	front := renderer.camera_get_front(app.cam)
	right := renderer.camera_get_right(app.cam)
	speed := 3.0 * dt

	if app.keys[int(sdl.Scancode.W)] do app.cam.pos += front * speed
	if app.keys[int(sdl.Scancode.S)] do app.cam.pos -= front * speed
	if app.keys[int(sdl.Scancode.D)] do app.cam.pos += right * speed
	if app.keys[int(sdl.Scancode.A)] do app.cam.pos -= right * speed
	if app.keys[int(sdl.Scancode.SPACE)] do app.cam.pos.y += speed
	if app.keys[int(sdl.Scancode.LSHIFT)] do app.cam.pos.y -= speed
}

render_frame :: proc(app: ^App) {
	if app.next_frame > renderer.FLIGHT {
		gpu.semaphore_wait(app.render.frame_sem, app.next_frame - renderer.FLIGHT)
	}

	swapchain_tex := gpu.swapchain_acquire_next()
	fa := &app.render.frame_arenas[app.next_frame % renderer.FLIGHT]
	gpu.arena_free_all(fa)

	cmd := gpu.commands_begin(.Main)

	aspect := f32(app.win_w) / f32(app.win_h)

	scene_data := gpu.arena_alloc(fa, renderer.Scene_Data)
	scene_data.cpu.view_proj = renderer.camera_get_vp(app.cam, aspect)

	frag_data := gpu.arena_alloc(fa, renderer.Frag_Data)
	frag_data.cpu.base_color = {1.0, 0.5, 0.2, 1.0}

	gpu.cmd_begin_render_pass(
		cmd,
		{
			color_attachments = {
				{texture = swapchain_tex, load_op = .Clear, clear_color = {0.1, 0.1, 0.15, 1.0}},
			},
		},
	)

	gpu.cmd_set_raster_state(cmd, gpu.Raster_State{.Triangle_List, .Cull_CCW, true})
	gpu.cmd_set_shaders(cmd, app.shaders[.Vertex], app.shaders[.Fragment])

	if app.model_loaded {
		for sem in renderer.Attribute_Semantic {
			scene_data.cpu.attributes[sem] = app.model.geometry.attributes[sem].gpu.ptr
		}
		scene_data.cpu.attr_mask = transmute(u32)app.model.geometry.attr_mask
		gpu.cmd_draw_indexed_indirect_multi(
			cmd,
			scene_data,
			frag_data,
			app.model.geometry.indices,
			app.model.geometry.draws,
			app.model.draw_count,
		)
	}

	gpu.cmd_end_render_pass(cmd)
	gpu.cmd_add_signal_semaphore(cmd, app.render.frame_sem, app.next_frame)
	gpu.queue_submit(.Main, {cmd})
	gpu.swapchain_present(.Main, app.render.frame_sem, app.next_frame)

	app.next_frame += 1
}

main :: proc() {
	console_logger := log.create_console_logger()
	defer log.destroy_console_logger(console_logger)
	context.logger = console_logger

	log.info("Starting application...")

	ok := sdl.Init(sdl.INIT_VIDEO)
	if !ok {
		log.error("Failed to initialize SDL")
		return
	}
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"no_gfx_api + cgltf",
		1280,
		720,
		{.VULKAN, .RESIZABLE, .HIGH_PIXEL_DENSITY},
	)

	if window == nil {
		log.error("Failed to create window")
		return
	}
	defer sdl.DestroyWindow(window)

	ok = sdl.SetWindowRelativeMouseMode(window, true)
	if !ok {
		log.warn("Failed to set relative mouse mode")
	}

	app: App
	init(&app, window)
	defer destroy(&app)

	run(&app)
	log.info("Application terminated successfully.")
}
