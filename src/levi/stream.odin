package levi

import "../gpu/gpu"

Stream_Attribute :: enum {
	Position,
	Color,
	Normal,
	UV0,
	Indices,
	Instances,
	Frame_Data_Stream,
}

@(rodata)
Stream_Element_Size: [Stream_Attribute]i64 = {
	.Position          = 16,
	.Color             = 16,
	.Normal            = 12,
	.UV0               = 8,
	.Indices           = size_of(u32),
	.Instances         = size_of(Instance_Data),
	.Frame_Data_Stream = size_of(Frame_Data),
}

@(rodata)
Stream_Max_Count: [Stream_Attribute]i64 = {
	.Position          = 1024 * 1024,
	.Color             = 1024 * 1024,
	.Normal            = 1024 * 1024,
	.UV0               = 1024 * 1024,
	.Indices           = 1024 * 1024 * 3,
	.Instances         = 1048576,
	.Frame_Data_Stream = 1,
}

@(rodata)
Stream_Memory_Type: [Stream_Attribute]gpu.Memory = {
	.Position          = gpu.Memory.GPU,
	.Color             = gpu.Memory.GPU,
	.Normal            = gpu.Memory.GPU,
	.UV0               = gpu.Memory.GPU,
	.Indices           = gpu.Memory.GPU,
	.Instances         = gpu.Memory.Default,
	.Frame_Data_Stream = gpu.Memory.Default,
}
