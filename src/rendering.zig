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
var font: Font = undefined;

const Direction = enum(u4) {
    North,
    South,
    East,
    West,
};

fn directionToVec2(d: Direction) Vec2 {
    return switch (d) {
        .North => Vec2.init(0, 1),
        .South => Vec2.init(0, -1),
        .East => Vec2.init(1, 0),
        .West => Vec2.init(-1, 0),
    };
}

const DirectionalSprites = struct {
    sprites: [4]Sprite,
};

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

    font = try makeFont("assets/font.png");

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

const Font = struct {
    sprites: [10]Sprite,
};

fn makeFont(path: []const u8) !Font {
    const im = try image.load(path);
    defer im.deinit();

    const crops = [_]image.Rect{
        .{ .x0 = 1, .y0 = 0, .x1 = 16, .y1 = 18 },
        .{ .x0 = 19, .y0 = 0, .x1 = 33, .y1 = 18 },
        .{ .x0 = 36, .y0 = 0, .x1 = 49, .y1 = 18 },
        .{ .x0 = 53, .y0 = 0, .x1 = 66, .y1 = 18 },
        .{ .x0 = 69, .y0 = 0, .x1 = 83, .y1 = 18 },
        .{ .x0 = 88, .y0 = 0, .x1 = 101, .y1 = 18 },
        .{ .x0 = 104, .y0 = 0, .x1 = 117, .y1 = 18 },
        .{ .x0 = 123, .y0 = 0, .x1 = 135, .y1 = 18 },
        .{ .x0 = 139, .y0 = 0, .x1 = 151, .y1 = 18 },
        .{ .x0 = 156, .y0 = 0, .x1 = 168, .y1 = 18 },
    };

    var f: Font = undefined;
    for (crops) |cr, i| {
        f.sprites[i] = try makeSpriteFromImage(try im.cropCopy(cr));
    }

    return f;
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
    const font_size = 0.5; // relative to cell size
    const letter_spacing = 0.1; // relative to font size

    var buf: [16]u8 = undefined;
    const buffer = buf[0..];
    const text = try std.fmt.bufPrint(buffer, "{}", .{game.sols()});

    const scaling = font_size * game.cell_size;
    const position = Vec2.init(10, game.window_height - 1.3 * scaling);
    var accumulated_width: f32 = position.x;
    for (text) |letter| {
        const sprite = font.sprites[letter - 48];
        var model = Mat4.eye();
        model.set(0, 0, scaling);
        model.set(1, 1, scaling);
        model.set(0, 3, accumulated_width);
        model.set(1, 3, position.y);
        accumulated_width += (sprite.width + letter_spacing) * scaling;

        try drawSpriteWithView(sprite, model, Mat4.eye());
    }
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
