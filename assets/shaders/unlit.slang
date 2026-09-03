import "../shaders/shared/shared.slang";

enum VertexAttribute {
  POSITION = 0,
  COLOR = 1,
  NORMAL = 2,
  UV0 = 3,
  COUNT = 4,
};

struct FrameData {
  float4x4 view_proj;
};

struct InstanceData {
  uint mesh_id;
  uint material_instance;
  uint _pad0;
  uint _pad1;
  float4x4 transform;
};

struct MaterialParams {
  float4 base_color;
  float4 emissive;
};

struct DrawData {
  uint64_t attributes[(int)VertexAttribute.COUNT];
  uint64_t instances;
  uint64_t material_params;
  uint64_t frame_data;
};

struct VertexOutput {
  float4 pos : SV_Position;
  float4 color : TEXCOORD0;
};

[shader("vertex")]
VertexOutput vertMain(uint vertex_id: SV_VertexID,
                      uint instance_id: SV_InstanceID,
                      GraphicsPipelineData<DrawData> data) {
  VertexOutput output;

  float3 *positions =
      (float3 *)data.vert.attributes[(int)VertexAttribute.POSITION];
  float4 *colors = (float4 *)data.vert.attributes[(int)VertexAttribute.COLOR];

  InstanceData *instances = (InstanceData *)data.vert.instances;
  MaterialParams *mat_params = (MaterialParams *)data.vert.material_params;
  FrameData *frame = (FrameData *)data.vert.frame_data;

  float3 local_pos = positions[vertex_id];
  float4 world_pos =
      mul(instances[instance_id].transform, float4(local_pos, 1.0));

  output.pos = mul(frame.view_proj, world_pos);
  output.color = colors[vertex_id] * mat_params[instance_id].base_color;

  return output;
}

[shader("fragment")]
float4 fragMain(VertexOutput input) : SV_Target { return input.color; }
