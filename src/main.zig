const std = @import("std");
const c = @cImport({
    @cInclude("epoxy/gl.h");
    @cInclude("GLFW/glfw3.h");
});

const game = @import("game.zig");
const rendering = @import("rendering.zig");

fn loadMap(path: []const u8) !game.Grid {
    const file = try std.fs.cwd().openFile(path, .{ .read = true });
    var buffer_: [5096]u8 = undefined;
    const bytes_read = try file.readAll(&buffer_);
    const buffer = buffer_[0..bytes_read];

    var cells = std.ArrayList(game.Cell).init(game.allocator);

    var n_rows: u32 = 0;
    for (buffer) |char| {
        switch (char) {
            // 'o' => try cells.append(.Dirt),
            // 'h' => try cells.append(.Hab),
            // 's' => try cells.append(.Spaceport),
            // 'g' => try cells.append(.Greenhouse),
            // 'f' => try cells.append(.Factory),
            '\n' => n_rows += 1,
            // ',' => {},
            else => try cells.append(.Dirt),
        }
    }

    return game.Grid{
        .rows = n_rows,
        .cols = @intCast(u32, cells.items.len) / n_rows,
        .cells = cells.toOwnedSlice(),
    };
}

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
            c.GLFW_KEY_A => if (game.player_velocity.x < 0) {
                game.player_velocity.x = 0;
            },
            c.GLFW_KEY_D => if (game.player_velocity.x > 0) {
                game.player_velocity.x = 0;
            },
            c.GLFW_KEY_S => if (game.player_velocity.y < 0) {
                game.player_velocity.y = 0;
            },
            c.GLFW_KEY_W => if (game.player_velocity.y > 0) {
                game.player_velocity.y = 0;
            },
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

    c.glClearColor(0, 0, 0, 0);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

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
