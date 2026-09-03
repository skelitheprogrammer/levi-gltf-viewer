package levi

import "../gpu/gpu"

Mesh_ID :: distinct u32
Material_ID :: distinct u32
Shader_ID :: distinct u32
Instance_ID :: distinct u32

FLIGHT :: 3
INVALID_MESH_ID :: Mesh_ID(~u32(0))
INVALID_MATERIAL_ID :: Material_ID(~u32(0))
INVALID_SHADER_ID :: Shader_ID(~u32(0))
INVALID_INSTANCE_ID :: Instance_ID(~u32(0))

Vertex_Attribute :: enum {
	Position,
	Color,
	Normal,
	UV0,
}

Instance_Data :: struct #align (16) {
	mesh_id:      Mesh_ID,
	material_id:  Material_ID,
	_pad0, _pad1: u32, // <--- CRITICAL FIX: Forces transform to offset 16
	transform:    [16]f32,
}

Material_Params :: struct #align (16) {
	base_color: [4]f32,
	emissive:   [4]f32,
}

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

Mesh_Desc :: struct {
	attributes: [Vertex_Attribute][]u8,
	indices:    []u32,
}

Mesh_Info :: struct #align (16) {
	pos_offset:   u32,
	pos_count:    u32,
	index_offset: u32,
	index_count:  u32,
	aabb_min:     [3]f32,
	aabb_max:     [3]f32,
}

Material_Template :: struct {
	vert:        Shader_ID,
	frag:        Shader_ID,
	params_size: u32,
}

Extract_Result :: struct {
	transform: [16]f32,
	params:    Material_Params,
}

Extract_Fn :: proc(id: Instance_ID, user_data: rawptr) -> Extract_Result

Render_Context :: struct {
	cmd_buf:     gpu.Command_Buffer,
	target:      gpu.Texture,
	frame_arena: ^gpu.Arena,
	renderer:    ^Renderer,
}

Render_Pass :: proc(ctx: ^Render_Context)

Stream_Attribute :: enum {
	Position,
	Color,
	Normal,
	UV0,
	Indices,
	Meshes,
	Instances,
	Material_Params_Stream,
	Frame_Data_Stream,
	Indirect_Commands,
	Draw_Count,
}

@(rodata)
Stream_Element_Size: [Stream_Attribute]i64 = {
	.Position               = size_of([4]f32),
	.Color                  = size_of([4]f32),
	.Normal                 = size_of([3]f32),
	.UV0                    = size_of([2]f32),
	.Indices                = size_of(u32),
	.Meshes                 = size_of(Mesh_Info),
	.Instances              = size_of(Instance_Data),
	.Material_Params_Stream = size_of(Material_Params),
	.Frame_Data_Stream      = size_of(Frame_Data),
	.Indirect_Commands      = size_of(Indirect_Draw),
	.Draw_Count             = size_of(u32),
}

@(rodata)
Stream_Max_Count: [Stream_Attribute]i64 = {
	.Position               = 1024 * 1024,
	.Color                  = 1024 * 1024,
	.Normal                 = 1024 * 1024,
	.UV0                    = 1024 * 1024,
	.Indices                = 1024 * 1024 * 3,
	.Meshes                 = 10000,
	.Instances              = 1048576,
	.Material_Params_Stream = 1048576,
	.Frame_Data_Stream      = 1,
	.Indirect_Commands      = 100000,
	.Draw_Count             = 1,
}

@(rodata)
Stream_Memory_Type: [Stream_Attribute]gpu.Memory = {
	.Position               = gpu.Memory.GPU,
	.Color                  = gpu.Memory.GPU,
	.Normal                 = gpu.Memory.GPU,
	.UV0                    = gpu.Memory.GPU,
	.Indices                = gpu.Memory.GPU,
	.Meshes                 = gpu.Memory.GPU,
	.Instances              = gpu.Memory.Default,
	.Material_Params_Stream = gpu.Memory.Default,
	.Frame_Data_Stream      = gpu.Memory.Default,
	.Indirect_Commands      = gpu.Memory.GPU,
	.Draw_Count             = gpu.Memory.GPU,
}
