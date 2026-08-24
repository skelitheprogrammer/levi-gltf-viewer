package levi

Error_Code :: enum {
	None,
	SDL_Init,
	Window_Creation,
	GPU_Init,
	File_Read,
	Parse_Failed,
	Missing_Position,
	Shader_Compile,
	GPU_Alloc,
}
