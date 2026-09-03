package levi

import "../gpu/gpu"
import "vendor:sdl3"

Render_State :: struct {
	frame_semaphore: gpu.Semaphore,
	frame_arenas:    [FLIGHT]gpu.Arena,
	frame_index:     u64,
}

Renderer :: struct {
	streams:   [Stream_Attribute]gpu.gpuptr,
	heads:     [Stream_Attribute]u32,
	shaders:   [dynamic]gpu.Shader,
	meshes:    [dynamic]Mesh_Info,
	materials: [dynamic]Material_Template,
	instances: [dynamic]Instance_Data,
}

Engine :: struct {
	state:     Render_State,
	renderer:  Renderer,
	window:    rawptr,
	win_s:     [2]i32,
	extract:   Extract_Fn,
	user_data: rawptr,
	passes:    [dynamic]Render_Pass,
}

engine_init :: proc(window: ^sdl3.Window, width, height: i32) -> ^Engine {
	eng := new(Engine)
	eng.window = window
	eng.win_s = {width, height}


	_ = gpu.init()
	gpu.swapchain_create_from_sdl(window, u32(FLIGHT))

	eng.state.frame_semaphore = gpu.semaphore_create(0)
	for i in 0 ..< FLIGHT {
		eng.state.frame_arenas[i] = gpu.arena_create()
	}

	for attr in Stream_Attribute {
		p := gpu.mem_alloc_raw(
			Stream_Element_Size[attr],
			Stream_Max_Count[attr],
			16,
			Stream_Memory_Type[attr],
		)
		eng.renderer.streams[attr] = p.gpu
		eng.renderer.heads[attr] = 0
	}

	return eng
}

engine_destroy :: proc(eng: ^Engine) {
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
	delete(eng.renderer.materials)
	delete(eng.renderer.instances)
	delete(eng.passes)
	free(eng)
}

draw :: proc(eng: ^Engine, frame_data: ^Frame_Data) {
	if eng.state.frame_index >= FLIGHT {
		gpu.semaphore_wait(eng.state.frame_semaphore, eng.state.frame_index - FLIGHT + 1)
	}

	target := gpu.swapchain_acquire_next()
	if target == {} {
		gpu.swapchain_resize({u32(eng.win_s[0]), u32(eng.win_s[1])})
		return
	}

	slot := int(eng.state.frame_index % FLIGHT)
	frame_arena := &eng.state.frame_arenas[slot]
	gpu.arena_free_all(frame_arena)

	cmd_buf := gpu.commands_begin(.Main)

	assert(eng.extract != nil, "extract function not set")
	instance_count := len(eng.renderer.instances)

	if instance_count > 0 {
		staging_inst := gpu.arena_alloc(frame_arena, Instance_Data, instance_count)
		staging_params := gpu.arena_alloc(frame_arena, Material_Params, instance_count)

		for i in 0 ..< instance_count {
			result := eng.extract(Instance_ID(i), eng.user_data)
			inst := eng.renderer.instances[i]
			inst.transform = result.transform
			staging_inst.cpu[i] = inst
			staging_params.cpu[i] = result.params
		}

		gpu.cmd_mem_copy_raw(
			cmd_buf,
			eng.renderer.streams[.Instances],
			staging_inst.gpu,
			size_of(Instance_Data) * instance_count,
		)
		gpu.cmd_mem_copy_raw(
			cmd_buf,
			eng.renderer.streams[.Material_Params_Stream],
			staging_params.gpu,
			size_of(Material_Params) * instance_count,
		)

		staging_cmds := gpu.arena_alloc(
			frame_arena,
			gpu.Draw_Indexed_Indirect_Command,
			instance_count,
		)
		staging_count := gpu.arena_alloc(frame_arena, u32, 1)

		for i in 0 ..< instance_count {
			mesh := eng.renderer.meshes[eng.renderer.instances[i].mesh_id]
			staging_cmds.cpu[i] = gpu.Draw_Indexed_Indirect_Command {
				index_count    = mesh.index_count,
				instance_count = 1,
				first_index    = mesh.index_offset,
				vertex_offset  = i32(mesh.pos_offset),
				first_instance = u32(i),
			}
		}
		staging_count.cpu[0] = u32(instance_count)

		gpu.cmd_mem_copy_raw(
			cmd_buf,
			eng.renderer.streams[.Indirect_Commands],
			staging_cmds.gpu,
			size_of(gpu.Draw_Indexed_Indirect_Command) * instance_count,
		)
		gpu.cmd_mem_copy_raw(
			cmd_buf,
			eng.renderer.streams[.Draw_Count],
			staging_count.gpu,
			size_of(u32),
		)
	}

	staging_frame := gpu.arena_alloc(frame_arena, Frame_Data, 1)
	staging_frame.cpu[0] = frame_data^
	gpu.cmd_mem_copy_raw(
		cmd_buf,
		eng.renderer.streams[.Frame_Data_Stream],
		staging_frame.gpu,
		size_of(Frame_Data),
	)

	// CRITICAL: Synchronize Transfer writes with Draw Indirect / Vertex Shader reads
	gpu.cmd_barrier(cmd_buf, .Transfer, .All, {})

	ctx := Render_Context {
		cmd_buf     = cmd_buf,
		target      = target,
		frame_arena = frame_arena,
		renderer    = &eng.renderer,
	}

	for pass in eng.passes {
		pass(&ctx)
	}

	gpu.cmd_add_signal_semaphore(cmd_buf, eng.state.frame_semaphore, eng.state.frame_index + 1)
	gpu.queue_submit(.Main, {cmd_buf})
	gpu.swapchain_present(.Main, eng.state.frame_semaphore, eng.state.frame_index + 1)
	eng.state.frame_index += 1
}
