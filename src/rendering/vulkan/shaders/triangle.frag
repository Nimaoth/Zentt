#version 450

layout(location = 0) in vec3 v_color;
layout(location = 1) in vec2 v_uv;

layout(set = 1, binding = 0) uniform sampler2D tex_sampler;

layout(location = 0) out vec4 f_color;
layout(location = 1) out uint f_id;

layout(push_constant) uniform UniformPushConstant {
    vec4 transform;
    vec2 uv_min;
    vec2 uv_max;
    uint id;
} pc;

void main() {
    f_color = texture(tex_sampler, mix(pc.uv_min, pc.uv_max, v_uv)).bgra * vec4(v_color, 1);
    f_color.rgb = pow(f_color.rgb, vec3(1/2.2));
    f_id = pc.id;
}
