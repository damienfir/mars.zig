#version 330 core

layout (location = 0) in vec2 coord;
layout (location = 1) in vec2 tex;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec2 texCoord;

void main(void) {
    gl_Position = projection * view * model * vec4(coord, 0.0, 1.0);
    texCoord = tex;
}
