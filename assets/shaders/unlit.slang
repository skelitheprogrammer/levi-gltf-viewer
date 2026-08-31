import "../shaders/shared/shared.slang";

enum VertexAttribute {
  COLOR = 0,
  COUNT = 1,
};

struct FrameData {
  float4x4 view_proj;
};

struct InstanceData {
  float4x4 transform;
};

struct DrawData {
  uint64_t frame_data;
  uint64_t instance_data;
  uint64_t position;
  uint64_t attributes[(int)VertexAttribute.COUNT];
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

  float4 *positions = (float4 *)data.vert.position;
  float4 *colors = (float4 *)data.vert.attributes[(int)VertexAttribute.COLOR];

  InstanceData *instances = (InstanceData *)data.vert.instance_data;
  FrameData *frame = (FrameData *)data.vert.frame_data;

  float4 local_position = positions[vertex_id];
  float4 world_position = mul(instances[instance_id].transform, local_position);

  output.pos = mul(frame.view_proj, world_position);
  output.color = colors[vertex_id];

  return output;
}

[shader("fragment")]
float4 fragMain(float4 color: TEXCOORD0) : SV_Target { return color; }
