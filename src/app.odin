package levi

import "core:log"
import "core:math"
import "core:math/linalg"
import sdl3 "vendor:sdl3"


Application :: struct {
	window:             ^sdl3.Window,
	renderer:           Renderer,
	camera:             Camera,
	scene:              Scene,
	running:            bool,
	pending_asset_path: string,
	orbit:              Orbit_State,
}

Orbit_State :: struct {
	target:   linalg.Vector3f32,
	distance: f32,
	yaw:      f32,
	pitch:    f32,
}

Scene :: struct {
	meshes:    [dynamic]Mesh_Data,
	instances: [dynamic]Mesh_Instance,
	loaded:    bool,
}

init :: proc(app: ^Application) -> Error_Code {
	app.running = true
	app.camera = Camera {
		fov    = 1.0472,
		aspect = 1280.0 / 720.0,
		near   = 0.01,
		far    = 1000.0,
	}

	if !sdl3.Init(sdl3.INIT_VIDEO) do return .SDL_Init

	window := sdl3.CreateWindow(
		"Levi Viewer",
		sdl3.WINDOWPOS_CENTERED,
		sdl3.WINDOWPOS_CENTERED,
		{.VULKAN},
	)
	if window == nil do return .Window_Creation
	app.window = window

	return renderer_init(&app.renderer)
}

destroy :: proc(app: ^Application) {
	unload_asset(app)
	renderer_destroy(&app.renderer)
	if app.window != nil do sdl3.DestroyWindow(app.window)
	sdl3.Quit()
}

run :: proc(app: ^Application) {
	for app.running {
		poll_events(app)

		if app.pending_asset_path != "" {
			load_asset(app, app.pending_asset_path)
			app.pending_asset_path = ""
		}

		update_orbit(app.orbit, &app.camera)

		renderer_begin_frame(&app.renderer)
		renderer_draw_scene(&app.renderer, app.camera, app.scene.meshes[:], app.scene.instances[:])
		renderer_end_frame(&app.renderer)
	}
}

queue_asset_load :: proc(app: ^Application, p: string) {
	app.pending_asset_path = p
}

load_asset :: proc(app: ^Application, p: string, allocator := context.allocator) {
	log.info("loading asset", "path", p)
	unload_asset(app)

	meshes, instances, err := load_gltf(&app.renderer, p, allocator)
	if err != .None {
		log.error("asset load failed", "code", err)
		return
	}
	append(&app.scene.meshes, ..meshes)
	append(&app.scene.instances, ..instances)

	bounds_min := linalg.Vector3f32{1e30, 1e30, 1e30}
	bounds_max := linalg.Vector3f32{-1e30, -1e30, -1e30}
	for mesh in app.scene.meshes {
		for i in 0 ..< 3 {
			bounds_min[i] = min(bounds_min[i], mesh.bounds_min[i])
			bounds_max[i] = max(bounds_max[i], mesh.bounds_max[i])
		}
	}

	center := (bounds_min + bounds_max) * 0.5
	extent := linalg.length(bounds_max - bounds_min)

	app.orbit.target = center
	app.orbit.distance = max(extent * 1.5, 1.0)
	app.orbit.yaw = 0.3
	app.orbit.pitch = 0.4
	app.camera.far = max(extent * 10.0, 100.0)
	app.scene.loaded = true
}

unload_asset :: proc(app: ^Application) {
	if !app.scene.loaded do return
	for mesh in app.scene.meshes do free_mesh(mesh)
	clear(&app.scene.meshes)
	clear(&app.scene.instances)
	app.scene.loaded = false
}

update_orbit :: proc(orbit: Orbit_State, cam: ^Camera) {
	cos_pitch := f32(math.cos(f64(orbit.pitch)))
	sin_pitch := f32(math.sin(f64(orbit.pitch)))
	sin_yaw := f32(math.sin(f64(orbit.yaw)))
	cos_yaw := f32(math.cos(f64(orbit.yaw)))

	offset := linalg.Vector3f32{cos_pitch * sin_yaw, sin_pitch, cos_pitch * cos_yaw}

	cam.position = orbit.target + offset * orbit.distance
	cam.forward = linalg.normalize(orbit.target - cam.position)
	cam.up = linalg.Vector3f32{0, 1, 0}
}

poll_events :: proc(app: ^Application) {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			app.running = false
		case .KEY_DOWN:
			if event.key.key == sdl3.K_F12 do app.running = false
		case .MOUSE_BUTTON_DOWN:
			app.orbit.yaw += event.motion.xrel * 0.005
			app.orbit.pitch += event.motion.yrel * 0.005
			app.orbit.pitch = max(-1.5, min(1.5, app.orbit.pitch))
		case .MOUSE_WHEEL:
			app.orbit.distance *= 1.0 - event.wheel.y * 0.1
			app.orbit.distance = max(0.1, min(1000.0, app.orbit.distance))
		}
	}
}
