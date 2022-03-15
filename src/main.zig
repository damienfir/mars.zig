const std = @import("std");
const c = @cImport({
    @cInclude("epoxy/gl.h");
    @cInclude("GLFW/glfw3.h");
});

const game = @import("game.zig");
const rendering = @import("rendering.zig");

fn glfw_key_callback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    _ = mods;
    _ = scancode;
    if (key == c.GLFW_KEY_ESCAPE and action == c.GLFW_PRESS) {
        c.glfwSetWindowShouldClose(window, 1);
    }

    if (action == c.GLFW_PRESS) {
        switch (key) {
            c.GLFW_KEY_A => game.player_velocity.x = -1,
            c.GLFW_KEY_W => game.player_velocity.y = 1,
            c.GLFW_KEY_D => game.player_velocity.x = 1,
            c.GLFW_KEY_S => game.player_velocity.y = -1,
            else => {},
        }
    } else if (action == c.GLFW_RELEASE) {
        switch (key) {
            c.GLFW_KEY_A, c.GLFW_KEY_D => game.player_velocity.x = 0,
            c.GLFW_KEY_S, c.GLFW_KEY_W => game.player_velocity.y = 0,
            else => {},
        }
    }
}

pub fn main() !void {
    _ = c.glfwInit();

    c.glfwWindowHint(c.GLFW_SAMPLES, 4);
    var window = c.glfwCreateWindow(game.window_width, game.window_height, "Mars", null, null);
    c.glfwMakeContextCurrent(window);
    c.glfwSetWindowPos(window, 100, 100);

    _ = c.glfwSetKeyCallback(window, glfw_key_callback);

    // c.glEnable(c.GL_DEPTH_TEST);
    c.glClearColor(0, 0, 0, 0);
    // c.glEnable(c.GL_BLEND);
    // c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

    var timer = try std.time.Timer.start();

    try game.init();
    try rendering.init();

    while (c.glfwWindowShouldClose(window) == 0) {
        const dt = @intToFloat(f32, timer.lap()) / 1e9;

        c.glClear(c.GL_COLOR_BUFFER_BIT);

        try game.update(dt);
        try rendering.draw();

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    _ = c.glfwTerminate();
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
