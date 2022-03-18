const std = @import("std");
const c = @cImport({
    @cInclude("epoxy/gl.h");
});
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const game = @import("game.zig");
const image = @import("image.zig");

const c_allocator = std.heap.c_allocator;

var shader_color: Shader = undefined;
var shader_sprite: Shader = undefined;
var grid_sprites: [10]ColorSprite = undefined;
var player_sprite: Sprite = undefined;
var player_sprites: DirectionalSprites = undefined;
var hab_sprite: Sprite = undefined;
var spaceport_sprite: Sprite = undefined;
var font_small: Font = undefined;
var font_large: Font = undefined;

const Direction = enum(u4) {
    North,
    South,
    East,
    West,
};

const ColorSprite = struct {
    vao: c.GLuint,
    color: Vec3,
};

const Sprite = struct {
    vao: c.GLuint,
    texture: c.GLuint,
    width: f32,
    height: f32,
};

const DirectionalSprites = struct {
    sprites: [4]Sprite,
};

fn directionToVec2(d: Direction) Vec2 {
    return switch (d) {
        .North => Vec2.init(0, 1),
        .South => Vec2.init(0, -1),
        .East => Vec2.init(1, 0),
        .West => Vec2.init(-1, 0),
    };
}

pub fn init() !void {
    grid_sprites[@enumToInt(game.Cell.Dirt)] = makeColorSprite(Vec3.init(0.8, 0.45, 0.1));
    grid_sprites[@enumToInt(game.Cell.Building)] = makeColorSprite(Vec3.init(0.3, 0.3, 0.3));
    grid_sprites[@enumToInt(game.Cell.Hab)] = makeColorSprite(Vec3.init(0.8, 0.8, 0.8));
    grid_sprites[@enumToInt(game.Cell.Greenhouse)] = makeColorSprite(Vec3.init(0.1, 0.6, 0.1));
    grid_sprites[@enumToInt(game.Cell.Factory)] = makeColorSprite(Vec3.init(0.1, 0.45, 0.8));
    grid_sprites[@enumToInt(game.Cell.Spaceport)] = makeColorSprite(Vec3.init(0.5, 0.5, 0.5));

    player_sprite = try makeSprite("assets/player-south.png");
    player_sprites.sprites[@enumToInt(Direction.North)] = try makeSprite("assets/player-north.png");
    player_sprites.sprites[@enumToInt(Direction.South)] = try makeSprite("assets/player-south.png");
    player_sprites.sprites[@enumToInt(Direction.East)] = try makeSprite("assets/player-east.png");
    player_sprites.sprites[@enumToInt(Direction.West)] = try makeSprite("assets/player-west.png");

    hab_sprite = try makeSprite("assets/hab.png");
    spaceport_sprite = try makeSprite("assets/spaceport.png");

    try makeFont();

    shader_color = try Shader.init("shaders/vertex.glsl", "shaders/fragment.glsl");
    shader_sprite = try Shader.init("shaders/vertex_sprite.glsl", "shaders/fragment_sprite.glsl");
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

const Font = struct {
    tex: c.GLuint,
    vao: c.GLuint,
    offsets: []usize,
    widths: []f32,

    pub fn definit(f: Font) void {
        game.allocator.free(f.offsets);
        game.allocator.free(f.widths);
    }

    pub fn draw(f: Font, text: []const u8, position: Vec2) !void {
        const font_size = 0.5; // relative to cell size
        const letter_spacing = 0.12; // relative to font size

        const scaling = font_size * game.cell_size;
        var accumulated_width: f32 = position.x;

        shader_sprite.use();
        defer shader_sprite.unuse();

        c.glBindTexture(c.GL_TEXTURE_2D, f.tex);
        c.glBindVertexArray(f.vao);
        defer c.glBindVertexArray(0);

        for (text) |char| {
            const char_index = char - 32;
            _ = char_index;
            var model = Mat4.eye();
            model.set(0, 0, scaling);
            model.set(1, 1, scaling);
            model.set(0, 3, accumulated_width);
            model.set(1, 3, position.y);
            accumulated_width += (f.widths[char_index] + letter_spacing) * scaling;

            try shader_sprite.set_mat4("model", model);
            try shader_sprite.set_mat4("view", Mat4.eye());
            try shader_sprite.set_mat4("projection", game.perpective);

            c.glDrawArrays(c.GL_TRIANGLES, @intCast(c_int, f.offsets[char_index]), 6);
            // c.glDrawArrays(c.GL_TRIANGLES, 17*6, 6);
        }
    }
};

fn makeFont() !void {
    const im = try image.load("assets/font2.png");
    defer im.deinit();

    var font: Font = undefined;
    c.glGenVertexArrays(1, &font.vao);
    c.glBindVertexArray(font.vao);
    defer c.glBindVertexArray(0);

    c.glGenTextures(1, &font.tex);
    c.glBindTexture(c.GL_TEXTURE_2D, font.tex);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA,
        @intCast(c_int, im.width),
        @intCast(c_int, im.height),
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        im.data.ptr,
    );
    c.glGenerateMipmap(c.GL_TEXTURE_2D);
    // const aspect_ratio = @intToFloat(f32, im.width) / @intToFloat(f32, im.height);

    // const crops = [_]usize{
    //     // format: x0 y0 w h
    //     169, 0, 3, 8, // Space
    //     169, 0, 3, 8, // !
    //     169, 0, 3, 8, // "
    //     169, 0, 3, 8, // #
    //     169, 0, 3, 8, // $
    //     169, 0, 3, 8, // %
    //     169, 0, 3, 8, // &
    //     169, 0, 3, 8, // '
    //     169, 0, 3, 8, // (
    //     169, 0, 3, 8, // )
    //     169, 0, 3, 8, // *
    //     169, 0, 3, 8, // +
    //     169, 0, 3, 8, // ,
    //     169, 0, 3, 8, // -
    //     169, 0, 3, 8, // .
    //     169, 0, 3, 8, // /
    //     0, 16, 4, 8, // 0
    //     5, 16, 3, 8, // 1
    //     9, 16, 4, 8, // 2
    //     14, 16, 4, 8, // 3
    //     19, 16, 4, 8, // 4
    //     24, 16, 4, 8, // 5
    //     29, 16, 4, 8, // 6
    //     34, 16, 4, 8, // 7
    //     39, 16, 4, 8, // 8
    //     44, 16, 4, 8, // 9
    //     169, 0, 3, 8, // :
    //     169, 0, 3, 8, // ;
    //     169, 0, 3, 8, // <
    //     169, 0, 3, 8, // =
    //     169, 0, 3, 8, // >
    //     169, 0, 3, 8, // ?
    //     169, 0, 3, 8, // @
    //     0, 0, 4, 8, // A
    //     5, 0, 4, 8, // B
    //     10, 0, 4, 8, // C
    //     15, 0, 4, 8, // D
    //     20, 0, 4, 8, // E
    //     25, 0, 4, 8, // F
    //     30, 0, 4, 8, // G
    //     35, 0, 4, 8, // H
    //     40, 0, 3, 8, // I
    //     44, 0, 4, 8, // J
    //     49, 0, 4, 8, // K
    //     54, 0, 4, 8, // L
    //     59, 0, 5, 8, // M
    //     65, 0, 5, 8, // N
    //     71, 0, 4, 8, // O
    //     76, 0, 4, 8, // P
    //     81, 0, 4, 8, // Q
    //     86, 0, 4, 8, // R
    //     91, 0, 4, 8, // S
    //     96, 0, 5, 8, // T
    //     102, 0, 4, 8, // U
    //     107, 0, 5, 8, // V
    //     113, 0, 5, 8, // W
    //     119, 0, 5, 8, // X
    //     125, 0, 5, 8, // Y
    //     131, 0, 4, 8, // Z
    //     169, 0, 3, 8, // [
    //     169, 0, 3, 8, // \
    //     169, 0, 3, 8, // ]
    //     169, 0, 3, 8, // ^
    //     169, 0, 3, 8, // _
    //     169, 0, 3, 8, // `
    //     0, 0, 4, 8, // a
    //     5, 0, 4, 8, // b
    //     10, 0, 4, 8, // c
    //     15, 0, 4, 8, // d
    //     20, 0, 4, 8, // e
    //     25, 0, 4, 8, // f
    //     30, 0, 4, 8, // g
    //     35, 0, 4, 8, // h
    //     40, 0, 3, 8, // i
    //     44, 0, 4, 8, // j
    //     49, 0, 4, 8, // k
    //     54, 0, 4, 8, // l
    //     59, 0, 5, 8, // m
    //     65, 0, 5, 8, // n
    //     71, 0, 4, 8, // o
    //     76, 0, 4, 8, // p
    //     81, 0, 4, 8, // q
    //     86, 0, 4, 8, // r
    //     91, 0, 4, 8, // s
    //     96, 0, 5, 8, // t
    //     81, 0, 4, 8, // u
    //     86, 0, 4, 8, // v
    //     91, 0, 4, 8, // w
    //     96, 0, 5, 8, // x
    //     96, 0, 5, 8, // y
    //     96, 0, 5, 8, // z
    // };

    const ascii_offset = 32;
    var crops = [_]usize{
        // format: x0 y0 w h
        166, 36, 6, 12, // Space
        166, 36, 6, 12, // !
        166, 36, 6, 12, // "
        166, 36, 6, 12, // #
        166, 36, 6, 12, // $
        166, 36, 6, 12, // %
        166, 36, 6, 12, // &
        166, 36, 6, 12, // '
        166, 36, 6, 12, // (
        166, 36, 6, 12, // )
        166, 36, 6, 12, // *
        166, 36, 6, 12, // +
        166, 36, 6, 12, // ,
        166, 36, 6, 12, // -
        166, 36, 6, 12, // .
        166, 36, 6, 12, // /
        0, 48, 5, 12, // 0
        0, 48, 3, 12, // 1
        0, 48, 5, 12, // 2
        0, 48, 5, 12, // 3
        0, 48, 5, 12, // 4
        0, 48, 5, 12, // 5
        0, 48, 5, 12, // 6
        0, 48, 5, 12, // 7
        0, 48, 5, 12, // 8
        0, 48, 5, 12, // 9
        166, 36, 6, 12, // :
        166, 36, 6, 12, // ;
        166, 36, 6, 12, // <
        166, 36, 6, 12, // =
        166, 36, 6, 12, // >
        166, 36, 6, 12, // ?
        166, 36, 6, 12, // @
        0, 24, 6, 12, // A
        0, 24, 6, 12, // B
        0, 24, 6, 12, // C
        0, 24, 6, 12, // D
        0, 24, 5, 12, // E
        0, 24, 5, 12, // F
        0, 24, 6, 12, // G
        0, 24, 6, 12, // H
        0, 24, 3, 12, // I
        0, 24, 5, 12, // J
        0, 24, 5, 12, // K
        0, 24, 5, 12, // L
        0, 24, 7, 12, // M
        0, 24, 7, 12, // N
        0, 24, 7, 12, // O
        0, 24, 6, 12, // P
        0, 24, 7, 12, // Q
        0, 24, 6, 12, // R
        0, 24, 5, 12, // S
        0, 24, 7, 12, // T
        0, 24, 6, 12, // U
        0, 24, 7, 12, // V
        0, 24, 8, 12, // W
        0, 24, 5, 12, // X
        0, 24, 7, 12, // Y
        0, 24, 6, 12, // Z
        166, 36, 6, 12, // [
        166, 36, 6, 12, // \
        166, 36, 6, 12, // ]
        166, 36, 6, 12, // ^
        166, 36, 6, 12, // _
        166, 36, 6, 12, // `
        0,  36, 6, 12, // a
        5,  36, 5, 12, // b
        10, 36, 4, 12, // c
        15, 36, 5, 12, // d
        20, 36, 5, 12, // e
        25, 36, 3, 12, // f
        30, 36, 5, 12, // g
        35, 36, 5, 12, // h
        40, 36, 1, 12, // i
        44, 36, 3, 12, // j
        49, 36, 4, 12, // k
        54, 36, 1, 12, // l
        59, 36, 7, 12, // m
        65, 36, 5, 12, // n
        71, 36, 5, 12, // o
        76, 36, 5, 12, // p
        81, 36, 5, 12, // q
        86, 36, 4, 12, // r
        91, 36, 5, 12, // s
        96, 36, 3, 12, // t
        81, 36, 5, 12, // u
        86, 36, 5, 12, // v
        91, 36, 7, 12, // w
        96, 36, 5, 12, // x
        96, 36, 4, 12, // y
        96, 36, 5, 12, // z
    };

    {
        var i: usize = '0' - ascii_offset;
        var acc: usize = 0;
        while (i <= '9' - ascii_offset) : (i += 1) {
            crops[i * 4] = acc;
            acc += crops[i * 4 + 2] + 1;
        }
    }

    {
        var i: usize = 'A' - ascii_offset;
        var acc: usize = 0;
        while (i <= 'Z' - ascii_offset) : (i += 1) {
            crops[i * 4] = acc;
            acc += crops[i * 4 + 2] + 1;
        }
    }

    {
        var i: usize = 'a' - ascii_offset;
        var acc: usize = 0;
        while (i <= 'z' - ascii_offset) : (i += 1) {
            crops[i * 4] = acc;
            acc += crops[i * 4 + 2] + 1;
        }
    }

    var vbo: c.GLuint = undefined;
    c.glGenBuffers(1, &vbo);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    defer c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

    var buffer: [crops.len * 6 * 4]f32 = undefined;
    var offsets = try game.allocator.alloc(usize, crops.len);
    var widths = try game.allocator.alloc(f32, crops.len);

    var i: u32 = 0;
    while (i < crops.len) : (i += 4) {
        const crop = crops[i .. i + 4];
        const x0 = @intToFloat(f32, crop[0]) / @intToFloat(f32, im.width);
        const y0 = @intToFloat(f32, crop[1]) / @intToFloat(f32, im.height);
        const x1 = @intToFloat(f32, crop[0] + crop[2]) / @intToFloat(f32, im.width);
        const y1 = @intToFloat(f32, crop[1] + crop[3]) / @intToFloat(f32, im.height);

        std.debug.assert(crop[2] < crop[3]);
        const x = @intToFloat(f32, crop[2]) / @intToFloat(f32, crop[3]);
        const vertices = [_]f32{
            //  vertex  texture
            0, 0, x0, y1,
            x, 0, x1, y1,
            0, 1, x0, y0,
            0, 1, x0, y0,
            x, 0, x1, y1,
            x, 1, x1, y0,
        };
        // const vertices = [_]f32{
        //     //  vertex  texture
        //     0, 0, 0, 0.1,
        //     1, 0, 0.1, 0.1,
        //     0, 1, 0, 0,
        //     0, 1, 0, 0,
        //     1, 0, 0.1, 0.1,
        //     1, 1, 0.1, 0,
        // };

        const offset = i * vertices.len;
        std.mem.copy(f32, buffer[offset .. offset + vertices.len], vertices[0..]);
        offsets[i / 4] = i * 6;
        widths[i / 4] = x;
    }

    // for (buffer[0..100]) |x| {
    //     std.debug.print("{d:.2}\n", .{x});
    // }

    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, buffer.len * @sizeOf(f32)), &buffer, c.GL_STATIC_DRAW);
    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), @intToPtr(*anyopaque, 2 * @sizeOf(f32)));
    c.glEnableVertexAttribArray(1);

    font.offsets = offsets;
    font.widths = widths;

    font_small = font;
}

fn makeSprite(path: []const u8) !Sprite {
    const im = try image.load(path);
    defer im.deinit();

    return try makeSpriteFromImage(im);
}

fn makeSpriteFromImage(im: image.Image) !Sprite {
    var sprite: Sprite = undefined;
    c.glGenVertexArrays(1, &sprite.vao);
    c.glBindVertexArray(sprite.vao);
    defer c.glBindVertexArray(0);

    c.glGenTextures(1, &sprite.texture);
    c.glBindTexture(c.GL_TEXTURE_2D, sprite.texture);

    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

    const borderColor = [_]f32{ 0, 0, 0, 0 };
    c.glTexParameterfv(c.GL_TEXTURE_2D, c.GL_TEXTURE_BORDER_COLOR, &borderColor);

    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA,
        @intCast(c_int, im.width),
        @intCast(c_int, im.height),
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        im.data.ptr,
    );
    c.glGenerateMipmap(c.GL_TEXTURE_2D);
    const aspect_ratio = @intToFloat(f32, im.width) / @intToFloat(f32, im.height);

    var vbo: c.GLuint = undefined;
    c.glGenBuffers(1, &vbo);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    defer c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

    var x: f32 = 1;
    var y = 1.0 / aspect_ratio;
    if (aspect_ratio < 1) {
        x = aspect_ratio;
        y = 1;
    }
    const vertices = [_]f32{
        //  vertex  texture
        0, 0, 0, 1,
        x, 0, 1, 1,
        0, y, 0, 0,
        0, y, 0, 0,
        x, 0, 1, 1,
        x, y, 1, 0,
    };
    sprite.width = x;
    sprite.height = y;

    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, 4 * 6 * @sizeOf(f32)), &vertices, c.GL_STATIC_DRAW);

    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(0);

    c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), @intToPtr(*anyopaque, 2 * @sizeOf(f32)));
    c.glEnableVertexAttribArray(1);

    return sprite;
}

fn makeColorSprite(color: Vec3) ColorSprite {
    var sprite: ColorSprite = undefined;
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

fn drawSpriteWithView(sprite: Sprite, model: Mat4, view: Mat4) !void {
    shader_sprite.use();
    defer shader_sprite.unuse();

    c.glBindTexture(c.GL_TEXTURE_2D, sprite.texture);
    c.glBindVertexArray(sprite.vao);
    defer c.glBindVertexArray(0);

    try shader_sprite.set_mat4("model", model);
    try shader_sprite.set_mat4("view", view);
    try shader_sprite.set_mat4("projection", game.perpective);

    c.glDrawArrays(c.GL_TRIANGLES, 0, 6);
}

fn drawSprite(sprite: Sprite, model: Mat4) !void {
    try drawSpriteWithView(sprite, model, game.view());
}

fn drawSpriteStatic(sprite: Sprite, model: Mat4) !void {
    try drawSpriteWithView(sprite, model, Mat4.eye());
}

fn drawColorSprite(sprite: ColorSprite, model: Mat4) !void {
    shader_color.use();
    defer shader_color.unuse();

    c.glBindVertexArray(sprite.vao);
    defer c.glBindVertexArray(0);

    try shader_color.set_mat4("model", model);
    try shader_color.set_mat4("view", game.view());
    try shader_color.set_mat4("projection", game.perpective);
    try shader_color.set_vec3("color", sprite.color);

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
    try drawColorSprite(grid_sprites[@enumToInt(cell)], model);
}

fn vec2ToDirection(v: Vec2) Direction {
    if (v.x > 0) {
        return .East;
    } else if (v.x < 0) {
        return .West;
    } else {
        if (v.y > 0) {
            return .North;
        } else {
            return .South;
        }
    }
}

fn drawBuilding(building: game.Building) !void {
    var model = Mat4.eye();
    model.set(0, 0, @intToFloat(f32, building.size) * game.cell_size);
    model.set(1, 1, @intToFloat(f32, building.size) * game.cell_size);
    model.set(0, 3, @intToFloat(f32, building.pos_x) * game.cell_size);
    model.set(1, 3, @intToFloat(f32, building.pos_y) * game.cell_size);

    const sprite = switch (building.class) {
        .Hab => hab_sprite,
        .Spaceport => spaceport_sprite,
        else => hab_sprite,
    };

    try drawSprite(sprite, model);
}

fn drawPlayer() !void {
    const p = game.player;
    var model = Mat4.eye();
    model.set(0, 0, game.player_size);
    model.set(1, 1, game.player_size);
    model.set(0, 3, p.x);
    model.set(1, 3, p.y);

    const direction = vec2ToDirection(game.player_velocity);

    try drawSprite(player_sprites.sprites[@enumToInt(direction)], model);
}

fn drawHud() !void {
    var buf: [32]u8 = undefined;
    const buffer = buf[0..];
    const text = try std.fmt.bufPrint(buffer, "SOL {}", .{game.sols()});
    const position = Vec2.init(10, game.window_height - 30);
    try font_small.draw(text, position);
}

pub fn draw() !void {
    var yi: u32 = 0;
    while (yi < game.currentScene().rows) : (yi += 1) {
        var xi: u32 = 0;
        while (xi < game.currentScene().cols) : (xi += 1) {
            const cell = game.currentScene().at(xi, yi);
            try drawCell(cell, xi, yi);
        }
    }

    for (game.currentScene().buildings.items) |building| {
        try drawBuilding(building);
    }

    try drawPlayer();

    try drawHud();
}
