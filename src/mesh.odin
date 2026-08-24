package levi

import "core:math/linalg"
import gpu "gpu/gpu"

Vertex_Attribute :: enum u32 {
	None,
	Position,
	Normal,
	Texcoord,
	Color,
}

Vertex_Mask :: bit_set[Vertex_Attribute;u32]

Mesh_Data :: struct {
	vertex_mask:  Vertex_Mask,
	vertex_count: u32,
	index_count:  u32,
	bounds_min:   linalg.Vector3f32,
	bounds_max:   linalg.Vector3f32,
	backing:      gpu.gpuptr,
	attributes:   [Vertex_Attribute]gpu.gpuptr,
	index_ptr:    gpu.gpuptr,
	indirect_ptr: gpu.gpuptr,
}

Mesh_Instance :: struct {
	mesh_index: u32,
	model:      linalg.Matrix4f32,
}

Vertex_Data :: struct #packed {
	positions: rawptr,
	normals:   rawptr,
	uvs:       rawptr,
}

Frame_Data :: struct #packed {
	view_proj: linalg.Matrix4f32,
}

Draw_Data :: struct #packed {
	model: linalg.Matrix4f32,
	color: [4]f32,
}

// Packed indirect command that includes push-constant-style Draw_Data
Indirect_Command :: struct #packed {
	using cmd: gpu.Draw_Indexed_Indirect_Command,
	data:      Draw_Data,
}
