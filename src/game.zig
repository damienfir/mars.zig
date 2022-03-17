const std = @import("std");
const Allocator = std.mem.Allocator;

const Mat4 = @import("math.zig").Mat4;
const Vec2 = @import("math.zig").Vec2;

pub const window_width: f32 = 800;
pub const window_ratio: f32 = 4.0 / 3.0;
pub const window_height: f32 = window_width / window_ratio;

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

pub var cell_size: f32 = undefined;
pub var player_size: f32 = undefined;
pub var player: Vec2 = undefined;
pub var player_velocity: Vec2 = Vec2.init(0, 0);
pub var camera = Vec2.init(0, 0);
pub const perpective = Mat4.orthographic(0, window_width, 0, window_height, -1, 1);

pub var scenes: [4]Grid = undefined;
pub var current_scene: u32 = 0;

const cells_per_second = 7;

pub const Building = struct {
    size: u32,
    pos_x: u32,
    pos_y: u32,
    class: BuildingType,
};

pub const BuildingType = enum {
    Hab,
    Factory,
    Spaceport,
    Greenhouse,
};

pub const Cell = enum(u8) {
    Dirt,
    Building,
    Hab,
    Factory,
    Spaceport,
    Greenhouse,
};

const ticks_per_second = 10;
const ticks_per_sol = 10;

pub const HudState = struct {
    ticks: u64 = 0,
    fractional_ticks: f32 = 0,
};

pub var hud_state = HudState{};

pub const Grid = struct {
    cells: []Cell,
    rows: u32,
    cols: u32,
    buildings: std.ArrayList(Building),

    pub fn init(rows: u32, cols: u32) !Grid {
        return Grid{
            .rows = rows,
            .cols = cols,
            .cells = try allocator.alloc(Cell, rows * cols),
            .buildings = std.ArrayList(Building).init(allocator),
        };
    }

    pub fn deinit(g: *Grid) void {
        gpa.allocator().free(g.cells);
    }

    pub fn at(g: Grid, x: u32, y: u32) Cell {
        return g.cells[y * g.cols + x];
    }

    pub fn buildingAt(g: Grid, x: u32, y: u32) ?usize {
        _ = x;
        _ = y;
        _ = g;
        return null;
    }

    pub fn set(g: Grid, x: u32, y: u32, cell: Cell) void {
        g.cells[y * g.cols + x] = cell;
    }

    pub fn fillZeros(g: *Grid) void {
        for (g.cells) |*cell| cell.* = .Dirt;
    }

    pub fn inBounds(g: Grid, x: u32, y: u32) bool {
        return x > 0 and x < g.cols and y > 0 and y < g.rows;
    }
};

pub fn init() !void {
    scenes[0] = try Grid.init(16, 16);
    scenes[0].fillZeros();
    try scenes[0].buildings.append(Building{
        .size = 5,
        .pos_x = 3,
        .pos_y = 12,
        .class = .Hab,
    });
    try scenes[0].buildings.append(Building{
        .size = 2,
        .pos_x = 12,
        .pos_y = 12,
        .class = .Spaceport,
    });
    current_scene = 0;

    cell_size = 50;
    player = Vec2.init(@intToFloat(f32, currentScene().cols) / 2.0, @intToFloat(f32, currentScene().rows) / 2.0).scale(cell_size);
    player_size = cell_size * 0.9;
}

pub fn currentScene() Grid {
    return scenes[current_scene];
}

pub fn view() Mat4 {
    return Mat4.translation2d(camera.sub(Vec2.init(window_width / 2, window_height / 2)).neg());
}

pub fn collide(position: Vec2) bool {
    const p = position.add(Vec2.init(player_size / 2, player_size / 2));
    const x = @floatToInt(u32, p.x / cell_size);
    const y = @floatToInt(u32, p.y / cell_size);
    if (!currentScene().inBounds(x, y) or currentScene().buildingAt(x, y) != null) {
        return true;
    }
    return false;
}

pub fn incrementTicks(dt: f32) void {
    const ticks_decimal = dt * @intToFloat(f32, ticks_per_second);
    var ticks_floored = std.math.floor(ticks_decimal);
    hud_state.ticks += @floatToInt(u64, ticks_floored);
    hud_state.fractional_ticks += ticks_decimal - ticks_floored;
    if (hud_state.fractional_ticks >= 1) {
        hud_state.ticks += 1;
        hud_state.fractional_ticks -= 1;
    }
}

pub fn update(dt: f32) !void {
    const vel = if (player_velocity.norm() > 0) player_velocity.normalize() else player_velocity;
    const player1 = player.add(vel.scale(dt * cells_per_second * cell_size));

    if (!collide(player1)) {
        player = player1;
    }

    camera = player;

    incrementTicks(dt);
}

pub fn sols() u64 {
    return hud_state.ticks / ticks_per_sol;
}
