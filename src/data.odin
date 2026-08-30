package main

import "levi"

Instance_Data :: struct #align (16) {
	model: matrix[4, 4]f32,
}

Frame_Data :: struct #align (16) {
	view_proj: matrix[4, 4]f32,
}

Unlit_Material :: struct #align (16) {
	base_color: [4]f32,
}

Unlit_Vertex_Layout :: enum {
	Position,
	Color,
}

Unlit_Vertex_Mapping :: [Unlit_Vertex_Layout]levi.Vertex_Attribute {
	.Position = .Position,
	.Color    = .Color,
}

Unlit_Vertex_Root :: struct #align (16) {
	streams:   [Unlit_Vertex_Layout]rawptr,
	instances: rawptr,
	frame:     rawptr,
}

Unlit_Pixel_Root :: struct #align (16) {
	materials: rawptr,
}
