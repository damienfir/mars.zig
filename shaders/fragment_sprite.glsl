#version 330

uniform sampler2D tex;
in vec2 texCoord;

out vec4 FragColor;

void main(void) {
    FragColor = texture(tex, texCoord);
}
