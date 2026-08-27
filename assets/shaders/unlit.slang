import "../shaders/shared/shared.slang";

enum VertexAttribute {
  COLOR = 0,
  COUNT = 1,
};

struct FrameData {
  float4x4 view_proj;
};

struct VertexData {
  uint64_t frame_data;
  uint64_t position;
  uint64_t attributes[(int)VertexAttribute.COUNT];
};

struct VertexOutput {
  float4 pos : SV_Position;
  float4 color : TEXCOORD0;
};

[shader("vertex")]
VertexOutput vertMain(uint vert_id: SV_VertexID,
                      GraphicsPipelineData<VertexData> data) {
  VertexOutput o;
  o.pos = float4(0.0, 0.0, 0.0, 1.0);
  o.color = float4(1.0, 1.0, 1.0, 1.0);

  if (data.vert.position == 0)
    return o;

  float4 *positions = (float4 *)data.vert.position;
  o.pos = positions[vert_id];

  if (data.vert.frame_data != 0) {
    FrameData *fd = (FrameData *)data.vert.frame_data;
    o.pos = mul(fd.view_proj, o.pos);
  }

  uint64_t color_addr = data.vert.attributes[(int)VertexAttribute.COLOR];
  if (color_addr != 0) {
    float4 *colors = (float4 *)color_addr;
    o.color = colors[vert_id];
  }

  return o;
}

[shader("fragment")]
float4 fragMain(float4 color: TEXCOORD0) : SV_Target { return color; }
