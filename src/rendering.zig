const std = @import("std");
const c = @cImport({
    @cInclude("epoxy/gl.h");
});
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const game = @import("game.zig");

const c_allocator = std.heap.c_allocator;

var shader: Shader = undefined;
var grid_sprites: [10]Sprite = undefined;
var player_sprite: Sprite = undefined;

pub fn init() !void {
    grid_sprites[@enumToInt(game.Cell.Dirt)] = makeSprite(Vec3.init(0.8, 0.45, 0.1));
    grid_sprites[@enumToInt(game.Cell.Building)] = makeSprite(Vec3.init(0.3, 0.3, 0.3));

    player_sprite = makeSprite(Vec3.init(0.2, 0.2, 0.2));

    shader = try Shader.init("shaders/vertex.glsl", "shaders/fragment.glsl");
}

pub const Shader = struct {
    program: c.GLuint,

    fn compile_shader_from_source(filename: []const u8, name: []const u8, kind: c.GLenum) !c.GLuint {
        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        var buffer: [5096]u8 = undefined;
        const bytes_read = try file.read(&buffer);
        const source = buffer[0..bytes_read];
        var vertex_shader = c.glCreateShader(kind);
        const source_ptr: ?[*]const u8 = source.ptr;
        const source_len = @intCast(c.GLint, source.len);
        c.glShaderSource(vertex_shader, 1, &source_ptr, &source_len);
        c.glCompileShader(vertex_shader);

        var ok: c.GLint = undefined;
        c.glGetShaderiv(vertex_shader, c.GL_COMPILE_STATUS, &ok);
        if (ok == 0) {
            var error_size: c.GLint = undefined;
            c.glGetShaderiv(vertex_shader, c.GL_INFO_LOG_LENGTH, &error_size);

            const log = try c_allocator.alloc(u8, @intCast(usize, error_size));
            defer c_allocator.free(log);
            c.glGetShaderInfoLog(vertex_shader, error_size, &error_size, log.ptr);
            std.debug.panic("Error compiling {s} shader: {s}", .{ name, log });
        }
        return vertex_shader;
    }

    pub fn init(vertex: []const u8, fragment: []const u8) !Shader {
        const vertex_shader = try compile_shader_from_source(vertex, "vertex", c.GL_VERTEX_SHADER);
        defer c.glDeleteShader(vertex_shader);
        const fragment_shader = try compile_shader_from_source(fragment, "fragment", c.GL_FRAGMENT_SHADER);
        defer c.glDeleteShader(fragment_shader);

        const program = c.glCreateProgram();
        c.glAttachShader(program, vertex_shader);
        c.glAttachShader(program, fragment_shader);
        c.glLinkProgram(program);

        var ok: c.GLint = undefined;
        c.glGetProgramiv(program, c.GL_LINK_STATUS, &ok);
        if (ok == 0) {
            var error_size: c.GLint = undefined;
            c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &error_size);

            const log = try c_allocator.alloc(u8, @intCast(usize, error_size));
            defer c_allocator.free(log);
            c.glGetProgramInfoLog(program, error_size, &error_size, log.ptr);
            std.debug.panic("Error linking program: {s}", .{log});
        }

        return Shader{ .program = program };
    }

    pub fn use(self: Shader) void {
        c.glUseProgram(self.program);
    }

    pub fn unuse(s: Shader) void {
        _ = s;
        c.glUseProgram(0);
    }

    pub fn glGetUniformLocation(self: Shader, name: []const u8) !c_int {
        const loc = c.glGetUniformLocation(self.program, name.ptr);
        if (loc == -1) {
            std.debug.panic("Cannot get uniform location: {s}", .{name});
        }
        return loc;
    }

    pub fn set_i32(self: Shader, name: []const u8, x: i32) !void {
        const loc = try self.glGetUniformLocation(name);
        c.glUniform1i(loc, x);
    }

    pub fn set_u32(self: Shader, name: []const u8, x: u32) !void {
        const loc = try self.glGetUniformLocation(name);
        c.glUniform1ui(loc, x);
    }

    pub fn set_vec3(self: Shader, name: []const u8, vec: Vec3) !void {
        const loc = try self.glGetUniformLocation(name);
        // TODO: use 3fv with pointer to data
        c.glUniform3f(loc, vec.x, vec.y, vec.z);
    }

    pub fn set_mat4(self: Shader, name: []const u8, mat: Mat4) !void {
        const loc = try self.glGetUniformLocation(name);
        c.glUniformMatrix4fv(loc, 1, c.GL_TRUE, &mat.data);
    }
};

const Sprite = struct {
    vao: c.GLuint,
    color: Vec3,
};

fn makeSprite(color: Vec3) Sprite {
    var sprite: Sprite = undefined;
    c.glGenVertexArrays(1, &sprite.vao);
    var vbo: c.GLuint = undefined;
    c.glGenBuffers(1, &vbo);
    c.glBindVertexArray(sprite.vao);
    defer c.glBindVertexArray(0);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    defer c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

    const vertices = [_]f32{ 0, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 1 };

    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, 2 * 6 * @sizeOf(f32)), &vertices, c.GL_STATIC_DRAW);
    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 0, null);
    c.glEnableVertexAttribArray(0);

    sprite.color = color;

    return sprite;
}

fn drawSprite(sprite: Sprite, model: Mat4) !void {
    c.glBindVertexArray(sprite.vao);
    defer c.glBindVertexArray(0);

    try shader.set_mat4("model", model);
    try shader.set_mat4("view", game.view());
    try shader.set_mat4("projection", game.perpective);
    try shader.set_vec3("color", sprite.color);

    c.glDrawArrays(c.GL_TRIANGLES, 0, 6);
}

fn drawCell(cell: game.Cell, xi: u32, yi: u32) !void {
    _ = cell;
    var model = Mat4.eye();
    const scaling: f32 = game.cell_size;
    model.set(0, 0, scaling);
    model.set(1, 1, scaling);
    model.set(0, 3, @intToFloat(f32, xi) * scaling);
    model.set(1, 3, @intToFloat(f32, yi) * scaling);
    try drawSprite(grid_sprites[@enumToInt(cell)], model);
}

fn drawPlayer() !void {
    const p = game.player;
    const scaling = game.cell_size * 0.8;
    var model = Mat4.eye();
    model.set(0, 0, scaling);
    model.set(1, 1, scaling);
    model.set(0, 3, p.x);
    model.set(1, 3, p.y);
    try drawSprite(player_sprite, model);
}

pub fn draw() !void {
    shader.use();
    defer shader.unuse();

    var yi: u32 = 0;
    while (yi < game.grid.rows) : (yi += 1) {
        var xi: u32 = 0;
        while (xi < game.grid.cols) : (xi += 1) {
            const cell = game.grid.at(xi, yi);
            try drawCell(cell, xi, yi);
        }
    }

    try drawPlayer();
}
