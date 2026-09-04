package levi

import "../gpu/gpu"
import "core:fmt"
import "core:mem"
import "vendor:sdl3"

Frame_Data :: struct #align (16) {
	view_proj: [16]f32,
}

Per_Draw_Data :: struct #align (4) {
	instance_index: u32,
}

Indirect_Draw :: struct {
	using cmd: gpu.Draw_Indexed_Indirect_Command,
	data:      Per_Draw_Data,
}

Vertex_Root :: struct {
	attributes:      [Vertex_Attribute]rawptr,
	instances:       rawptr,
	material_params: rawptr,
	frame_data:      rawptr,
}

Render_Context :: struct {
	cmd_buf:     gpu.Command_Buffer,
	target:      gpu.Texture,
	frame_arena: ^gpu.Arena,
	renderer:    ^Renderer,
	user_data:   rawptr,
	win_s:       [2]i32,
}

Render_Pass :: proc(ctx: ^Render_Context)
View_Extract_Fn :: proc(user_data: rawptr) -> Frame_Data

Render_State :: struct {
	frame_semaphore: gpu.Semaphore,
	frame_arenas:    [FLIGHT]gpu.Arena,
	frame_index:     u64,
}

Renderer :: struct {
	streams:         [Stream_Attribute]gpu.gpuptr,
	heads:           [Stream_Attribute]u32,
	shaders:         [dynamic]gpu.Shader,
	meshes:          [dynamic]Mesh_Info,
	material_types:  [dynamic]Material_Type_Info,
	material_assets: [dynamic]Material_Asset,
	instances:       [dynamic]Instance_Data,
}

Engine :: struct {
	state:        Render_State,
	renderer:     Renderer,
	window:       ^sdl3.Window,
	win_s:        [2]i32,
	user_data:    rawptr,
	view_extract: View_Extract_Fn,
	passes:       [dynamic]Render_Pass,
}

engine_init :: proc(
	window: ^sdl3.Window,
	width, height: i32,
	loc := #caller_location,
) -> (
	eng: ^Engine,
	err: Error,
) {
	if window == nil {
		log_error(.Invalid_Argument, loc)
		return nil, .Invalid_Argument
	}

	eng = new(Engine)
	eng.window = window
	eng.win_s = {width, height}

	log_levi("Initializing GPU subsystem...", loc)
	ok := gpu.init()
	if !ok {
		log_error(.Out_Of_Memory, loc)
		free(eng)
		return nil, .Out_Of_Memory
	}
	log_levi("GPU subsystem initialized.", loc)

	gpu.swapchain_create_from_sdl(window, u32(FLIGHT))

	eng.state.frame_semaphore = gpu.semaphore_create(0)
	for i in 0 ..< FLIGHT {
		eng.state.frame_arenas[i] = gpu.arena_create()
	}

	log_levi("Allocating rendering streams...", loc)
	for attr in Stream_Attribute {
		p := gpu.mem_alloc_raw(
			Stream_Element_Size[attr],
			Stream_Max_Count[attr],
			16,
			Stream_Memory_Type[attr],
		)
		if p.gpu == gpu.null {
			log_error(.Out_Of_Memory, loc)
			engine_destroy(eng)
			return nil, .Out_Of_Memory
		}
		eng.renderer.streams[attr] = p.gpu
		eng.renderer.heads[attr] = 0
	}

	log_levi("Engine initialization complete.", loc)
	return eng, .None
}

engine_destroy :: proc(eng: ^Engine, loc := #caller_location) {
	if eng == nil do return

	log_levi("Destroying engine...", loc)
	gpu.wait_idle()
	gpu.semaphore_destroy(eng.state.frame_semaphore)
	for i in 0 ..< FLIGHT {
		gpu.arena_destroy(&eng.state.frame_arenas[i])
	}
	for attr in Stream_Attribute {
		gpu.mem_free_raw(eng.renderer.streams[attr])
	}
	for shader in eng.renderer.shaders {
		gpu.shader_destroy(shader)
	}
	delete(eng.renderer.shaders)
	delete(eng.renderer.meshes)
	delete(eng.renderer.material_types)
	delete(eng.renderer.material_assets)
	delete(eng.renderer.instances)
	delete(eng.passes)
	free(eng)
	log_levi("Engine destroyed.", loc)
}

draw :: proc(eng: ^Engine, loc := #caller_location) -> Error {
	if eng == nil do return .Invalid_Argument
	if eng.view_extract == nil {
		log_error(.Invalid_Argument, loc)
		return .Invalid_Argument
	}

	if eng.state.frame_index >= FLIGHT {
		gpu.semaphore_wait(eng.state.frame_semaphore, eng.state.frame_index - FLIGHT + 1)
	}

	target := gpu.swapchain_acquire_next()
	if target == {} {
		gpu.swapchain_resize({u32(eng.win_s[0]), u32(eng.win_s[1])})
		return .None
	}

	slot := int(eng.state.frame_index % FLIGHT)
	frame_arena := &eng.state.frame_arenas[slot]
	gpu.arena_free_all(frame_arena)

	cmd_buf := gpu.commands_begin(.Main)

	staging_frame := gpu.arena_alloc(frame_arena, Frame_Data, 1)
	staging_frame.cpu[0] = eng.view_extract(eng.user_data)

	gpu.cmd_mem_copy_raw(
		cmd_buf,
		eng.renderer.streams[.Frame_Data_Stream],
		staging_frame.gpu,
		size_of(Frame_Data),
	)

	gpu.cmd_barrier(cmd_buf, .Transfer, .All, {})

	ctx := Render_Context {
		cmd_buf     = cmd_buf,
		target      = target,
		frame_arena = frame_arena,
		renderer    = &eng.renderer,
		user_data   = eng.user_data,
		win_s       = eng.win_s,
	}

	for pass in eng.passes {
		pass(&ctx)
	}

	gpu.cmd_add_signal_semaphore(cmd_buf, eng.state.frame_semaphore, eng.state.frame_index + 1)
	gpu.queue_submit(.Main, {cmd_buf})
	gpu.swapchain_present(.Main, eng.state.frame_semaphore, eng.state.frame_index + 1)
	eng.state.frame_index += 1

	return .None
}

draw_material_type :: #force_inline proc(ctx: ^Render_Context, mat_type: Material_Type_ID) {
	draw_material_type_internal(ctx, mat_type)
}

@(private)
draw_material_type_internal :: proc(ctx: ^Render_Context, mat_type: Material_Type_ID) {
	r := ctx.renderer
	if u32(mat_type) >= u32(len(r.material_types)) do return
	type_info := r.material_types[mat_type]

	count := 0
	for i in 0 ..< len(r.instances) {
		inst := r.instances[i]
		if r.material_assets[inst.mat_handle].type_id == mat_type {
			count += 1
		}
	}
	if count == 0 do return

	mat_data_size := len(r.material_assets) * MAX_MATERIAL_SIZE
	mat_staging := gpu.arena_alloc_raw(ctx.frame_arena, mat_data_size, 16)

	for i in 0 ..< len(r.material_assets) {
		if r.material_assets[i].type_id == mat_type {
			mem.copy(
				rawptr(uintptr(mat_staging.cpu) + uintptr(i * MAX_MATERIAL_SIZE)),
				raw_data(r.material_assets[i].data[:]),
				int(type_info.size),
			)
		}
	}

	staging_inst := gpu.arena_alloc(ctx.frame_arena, Instance_Data, count)
	staging_cmds := gpu.arena_alloc(ctx.frame_arena, Indirect_Draw, count)

	cmd_idx := 0
	for i in 0 ..< len(r.instances) {
		inst := r.instances[i]
		if r.material_assets[inst.mat_handle].type_id == mat_type {
			mesh := r.meshes[inst.mesh_id]

			staging_inst.cpu[cmd_idx] = inst

			staging_cmds.cpu[cmd_idx] = Indirect_Draw {
				cmd = gpu.Draw_Indexed_Indirect_Command {
					index_count = mesh.index_count,
					instance_count = 1,
					first_index = mesh.index_offset,
					vertex_offset = i32(mesh.pos_offset),
					first_instance = 0,
				},
				data = Per_Draw_Data{instance_index = u32(cmd_idx)},
			}
			cmd_idx += 1
		}
	}

	gpu.cmd_set_shaders(ctx.cmd_buf, r.shaders[type_info.vert], r.shaders[type_info.frag])

	root := gpu.arena_alloc(ctx.frame_arena, Vertex_Root)
	for attr in Vertex_Attribute {
		root.cpu.attributes[attr] = r.streams[Stream_Attribute(attr)].ptr
	}
	root.cpu.instances = staging_inst.gpu.ptr
	root.cpu.material_params = mat_staging.gpu.ptr
	root.cpu.frame_data = r.streams[.Frame_Data_Stream].ptr

	count_buf := gpu.arena_alloc(ctx.frame_arena, u32, 1)
	count_buf.cpu[0] = u32(count)

	gpu.cmd_draw_indexed_indirect_multi_raw(
		ctx.cmd_buf,
		root,
		{},
		r.streams[.Indices],
		.U32,
		staging_cmds.gpu,
		u32(size_of(Indirect_Draw)),
		count_buf.gpu,
	)
}
