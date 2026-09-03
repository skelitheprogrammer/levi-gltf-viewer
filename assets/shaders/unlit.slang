import "../shaders/shared/shared.slang";

enum VertexAttribute {
  POSITION = 0,
  COLOR = 1,
  NORMAL = 2,
  UV0 = 3,
};

struct VertexData {
  uint64_t attributes[4];
  uint64_t instances;
  uint64_t material_params;
  uint64_t frame_data;
};

struct InstanceData {
  uint mesh_id;
  uint material_instance;
  uint _pad0, _pad1;
  float4x4 transform;
};

struct MaterialParams {
  float4 base_color;
  float4 emissive;
};

struct FrameData {
  float4x4 view_proj;
};

// Per-draw user data. Matches Odin's Per_Draw_Data.
// Accessed via data.drawData in the shader.
struct PerDrawData {
  uint instance_index;
};

struct VSInput {
  uint vertexID : SV_VertexID;
};

struct VSOutput {
  float4 pos : SV_Position;
  float4 color : TEXCOORD0;
};

[shader("vertex")]
VSOutput
vertMain(VSInput input,
         GraphicsPipelineData<VertexData, void, PerDrawData> pipeline) {
  VSOutput output;

  float4 *positions =
      (float4 *)pipeline.vert.attributes[(int)VertexAttribute.POSITION];
  float4 *colors =
      (float4 *)pipeline.vert.attributes[(int)VertexAttribute.COLOR];
  InstanceData *instances = (InstanceData *)pipeline.vert.instances;
  MaterialParams *mat_params = (MaterialParams *)pipeline.vert.material_params;
  FrameData *frame = (FrameData *)pipeline.vert.frame_data;

  float4 local_pos = positions[input.vertexID];

  // Per-draw instance index from the indirect buffer's user data
  uint idx = pipeline.drawData.instance_index;

  float4 world_pos = mul(instances[idx].transform, local_pos);
  float4 clip_pos = mul(frame.view_proj, world_pos);

  output.pos = clip_pos;
  output.color = colors[input.vertexID] * mat_params[idx].base_color;

  return output;
}

[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target { return input.color; }
