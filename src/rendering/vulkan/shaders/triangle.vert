#version 450

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec3 a_color;
layout(location = 2) in vec2 a_uv;

layout(location = 0) out vec3 v_color;
layout(location = 1) out vec2 v_uv;

layout(binding = 0) uniform UniformBufferObject {
    mat4 view;
    mat4 proj;
} ubo;

layout(push_constant) uniform UniformPushConstant {
    vec4 transform;
} pc;

void main() {
    gl_Position = vec4((a_pos * pc.transform.zw + pc.transform.xy) * vec2(1, -1), 0.0, 1.0) * ubo.view * ubo.proj;
    v_color = a_color;
    v_uv = a_uv;
}
