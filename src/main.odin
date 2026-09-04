package main

import levi "../src/levi"
import "core:log"
import "core:math"
import "core:math/linalg"
import sdl "vendor:sdl3"

main :: proc() {
	logger := log.create_console_logger(.Info)
	context.logger = logger
	defer log.destroy_console_logger(logger)

	log.info("Initializing SDL...")
	ok := sdl.Init({.VIDEO})
	ensure(ok, "sdl is not initialized")
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Levi Viewer",
		1280,
		720,
		{.VULKAN, .RESIZABLE, .HIGH_PIXEL_DENSITY},
	)
	ensure(window != nil)
	defer sdl.DestroyWindow(window)
	_ = sdl.SetWindowRelativeMouseMode(window, true)

	eng, err := levi.engine_init(window, 1280, 720)
	if err != .None {
		log.error("Failed to initialize engine.")
		return
	}
	defer levi.engine_destroy(eng)

	app: App_State
	app.cam_state.pos = {0, 0, -3}
	app.cam = Camera {
		mode   = Perspective{linalg.to_radians(f32(60))},
		near   = 0.1,
		far    = 100.0,
		aspect = f32(eng.win_s[0]) / f32(eng.win_s[1]),
	}
	input: Input_State

	log.info("Loading assets...")
	vert, _ := levi.create_shader(eng, #load("../samples/triangle/unlit.vert.spv", []u32), .Vertex)
	frag, _ := levi.create_shader(
		eng,
		#load("../samples/triangle/unlit.frag.spv", []u32),
		.Fragment,
	)
	app.mat_type, _ = levi.register_material_type(Custom_Material, eng, vert, frag)
	mesh := create_quad(eng)

	app.red_mat, _ = levi.create_material_asset(
		eng,
		app.mat_type,
		Custom_Material{color = {1, 0, 0, 1}, time = 0.0},
	)
	green_mat, _ := levi.create_material_asset(
		eng,
		app.mat_type,
		Custom_Material{color = {0, 1, 0, 1}, time = 0.0},
	)

	id1, _ := levi.spawn_instance(eng, mesh, app.red_mat)
	append(
		&app.instances,
		My_Instance{pos = {1, 0, 0}, rot = linalg.QUATERNIONF32_IDENTITY, scale = {1, 1, 1}},
	)

	id2, _ := levi.spawn_instance(eng, mesh, green_mat)
	append(
		&app.instances,
		My_Instance{pos = {-1, 0, 0}, rot = linalg.QUATERNIONF32_IDENTITY, scale = {1, 1, 1}},
	)
	log.info("Assets loaded.")

	eng.user_data = &app
	eng.extract = extract_instance
	eng.view_extract = extract_view
	append(&eng.passes, my_opaque_pass)

	last_time := sdl.GetPerformanceCounter()
	ts_freq := sdl.GetPerformanceFrequency()

	log.info("Entering main loop...")
	for {
		if !poll_window_events(window, &input) do break

		now_ts := sdl.GetPerformanceCounter()
		delta_time := min(0.1, f32(f64((now_ts - last_time) * 1000) / f64(ts_freq)) / 1000.0)
		last_time = now_ts

		w, h: i32
		sdl.GetWindowSizeInPixels(window, &w, &h)
		eng.win_s = {w, h}
		if eng.win_s[0] == 0 || eng.win_s[1] == 0 do continue
		app.cam.aspect = f32(eng.win_s[0]) / f32(eng.win_s[1])

		update_camera(&app.cam_state, &input, delta_time)
		log.info(app.cam_state)

		app.instances[0].pos.y = math.sin(app.time) * 0.5
		app.time += delta_time

		levi.update_material_asset(
			eng,
			app.red_mat,
			Custom_Material{color = {1, 0, 0, 1}, time = app.time},
		)

		if draw_err := levi.draw(eng); draw_err != .None do log.error("Draw failed.")
	}
	log.info("Main loop exited.")
}
