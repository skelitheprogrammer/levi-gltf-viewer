package levi

import "core:math/linalg"
import gpu "gpu/gpu"


Renderer :: struct {
	state:        ^Render_State,
	cmd_buf:      gpu.Command_Buffer,
	swapchain:    gpu.Texture,
	sort_indices: [dynamic]u32,
	meshes:       [dynamic]Mesh_Data,
	instances:    [dynamic]Mesh_Instance,
}

renderer_init :: proc(r: ^Renderer, state: ^Render_State) -> Error_Code {
	r.state = state
	return .None
}

renderer_destroy :: proc(r: ^Renderer) {
	delete(r.sort_indices)
	delete(r.meshes)
	delete(r.instances)
	r^ = {}
}

renderer_begin_frame :: proc(r: ^Renderer) {
	rs := r.state
	flight_idx := render_state_flight_index(rs)

	gpu.arena_free_all(&rs.frame_arenas[flight_idx])

	if rs.frame_index >= FLIGHT {
		gpu.semaphore_wait(rs.sem, rs.frame_index - FLIGHT)
	}

	r.swapchain = gpu.swapchain_acquire_next()
	r.cmd_buf = gpu.commands_begin(.Main)

	gpu.cmd_begin_render_pass(
		r.cmd_buf,
		gpu.Render_Pass_Desc {
			color_attachments = {
				{
					texture = r.swapchain,
					load_op = .Clear,
					store_op = .Store,
					clear_color = {0.08, 0.08, 0.1, 1.0},
				},
			},
		},
	)

	gpu.cmd_set_depth_state(r.cmd_buf, gpu.Depth_State{mode = {.Read, .Write}, compare = .Less})
	gpu.cmd_set_raster_state(
		r.cmd_buf,
		gpu.Raster_State{topology = .Triangle_List, cull_mode = .Cull_CCW},
	)
}

renderer_end_frame :: proc(r: ^Renderer) {
	rs := r.state

	gpu.cmd_end_render_pass(r.cmd_buf)
	gpu.queue_submit(.Main, {r.cmd_buf})
	gpu.swapchain_present(.Main, rs.sem, rs.frame_index)

	rs.frame_index += 1
}

renderer_upload_mesh :: proc(r: ^Renderer, staging: Staging_Data) {
	rs := r.state

	cmd_buf := gpu.commands_begin(.Transfer)
	mesh := transfer_staging_to_gpu(cmd_buf, staging)
	gpu.cmd_barrier(cmd_buf, .Transfer, .All, {})
	gpu.queue_submit(.Transfer, {cmd_buf})
	gpu.queue_wait_idle(.Transfer)

	append(&r.meshes, mesh)
}

renderer_draw_meshes :: proc(r: ^Renderer, view_proj: linalg.Matrix4f32) {
	if len(r.meshes) == 0 {return}

	frame_data: Frame_Data
	frame_data.view_proj = view_proj

	for instance, _ in r.instances {
		mesh := &r.meshes[instance.mesh_index]
		if mesh.indirect_ptr.ptr == nil {continue}

	}
}


transfer_staging_to_gpu :: proc(
	cmd_buf: gpu.Command_Buffer,
	staging: Staging_Data,
) -> (
	res: Mesh_Data,
) {

	res.vertex_mask = staging.vertex_mask
	res.vertex_count = staging.vertex_count
	res.index_count = staging.index_count
	res.bounds_min = staging.bounds_min
	res.bounds_max = staging.bounds_max

	total_bytes: i64
	for slice, _ in staging.attributes {
		total_bytes += i64(len(slice.cpu))
	}
	total_bytes += i64(len(staging.indices.cpu))

	if total_bytes == 0 {return}

	backing := gpu.mem_alloc(u8, i32(total_bytes), gpu.Memory.GPU)
	res.backing = backing.gpu

	offset: i64 = 0
	for slice, attr in staging.attributes {
		if len(slice.cpu) == 0 {continue}

		size := i64(len(slice.cpu))
		region := gpu.subslice(backing, offset, offset + size)
		gpu.cmd_mem_copy(cmd_buf, region, slice)

		res.attributes[attr] = region.gpu
		offset += size
	}

	if len(staging.indices.cpu) > 0 {
		size := i64(len(staging.indices.cpu))
		region := gpu.subslice(backing, offset, offset + size)
		gpu.cmd_mem_copy(cmd_buf, region, staging.indices)
		res.index_ptr = region.gpu
	}

	if len(staging.commands.cpu) > 0 {
		indirect := gpu.mem_alloc(Indirect_Command, i32(len(staging.commands.cpu)), gpu.Memory.GPU)
		gpu.cmd_mem_copy(cmd_buf, indirect, staging.commands)
		res.indirect_ptr = indirect.gpu
	}

	return res
}
