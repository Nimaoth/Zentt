#version 450

layout(location = 0) in vec3 v_color;
layout(location = 1) in vec2 v_uv;

layout(set = 1, binding = 0) uniform sampler2D tex_sampler;

layout(location = 0) out vec4 f_color;

void main() {
    f_color = texture(tex_sampler, v_uv).bgra * vec4(v_color, 1);
    f_color.rgb = pow(f_color.rgb, vec3(1/2.2));
    // f_color = vec4(v_color, 1.0);
}
