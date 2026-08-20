// assets/shaders/unlit.slang
import "../shaders/shared/shared.slang";

static const uint POSITION_BIT = 1u << 0;
static const uint NORMAL_BIT   = 1u << 1;
static const uint UV_BIT       = 1u << 2;
static const uint COLOR_BIT    = 1u << 3;

struct VertexData {
  float4x4 viewProj;
  uint64_t attributes[4];
  uint attrMask;
};

struct FragmentData {
  float4 baseColor;
};

struct VSInput {
  uint vertexID : SV_VertexID;
};

struct VSOutput {
  float4 pos : SV_Position;
  float3 normal : NORMAL;
};

[shader("vertex")]
VSOutput vertMain(VSInput input,
                  GraphicsPipelineData<VertexData, FragmentData> pipeline) {
  VSOutput output;

  float3 *positions = (float3 *)pipeline.vert->attributes[0];
  float3 pos = positions[input.vertexID];
  output.pos = mul(pipeline.vert->viewProj, float4(pos, 1.0));

  float3 normal = float3(0.0, 0.0, 0.0);
  if ((pipeline.vert->attrMask & NORMAL_BIT) != 0) {
    float3 *normals = (float3 *)pipeline.vert->attributes[1];
    normal = normals[input.vertexID];
  }
  output.normal = normal;

  return output;
}

struct PSInput {
  float4 pos : SV_Position;
  float3 normal : NORMAL;
};

[shader("fragment")]
float4 fragMain(PSInput input,
                GraphicsPipelineData<VertexData, FragmentData> pipeline) {
  if ((pipeline.vert->attrMask & NORMAL_BIT) != 0) {
    float3 n = normalize(input.normal);
    return float4(n * 0.5 + 0.5, 1.0);
  }
  return pipeline.frag->baseColor;
}
