const std = @import("std");
const Allocator = std.mem.Allocator;

const Mat4 = @import("math.zig").Mat4;
const Vec2 = @import("math.zig").Vec2;

pub const window_width: f32 = 800;
pub const window_ratio: f32 = 4.0 / 3.0;
pub const window_height: f32 = window_width / window_ratio;

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

pub const perpective = Mat4.orthographic(0, window_width, 0, window_height, -1, 1);

pub var grid: Grid = undefined;
pub var cell_size: f32 = undefined;
pub var player_size: f32 = undefined;

pub var player: Vec2 = undefined;

pub var player_velocity: Vec2 = Vec2.init(0, 0);

pub var camera = Vec2.init(0, 0);

pub const Cell = enum(u8) {
    Dirt,
    Building,
    Hab,
    Factory,
    Spaceport,
    Greenhouse,
};

pub const Grid = struct {
    cells: []Cell,
    rows: u32,
    cols: u32,

    pub fn init(rows: u32, cols: u32) !Grid {
        return Grid{
            .rows = rows,
            .cols = cols,
            .cells = try gpa.allocator().alloc(Cell, rows * cols),
        };
    }

    pub fn deinit(g: *Grid) void {
        gpa.allocator().free(g.cells);
    }

    pub fn at(g: Grid, x: u32, y: u32) Cell {
        return g.cells[y * g.cols + x];
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
    // const n_rows = 30;
    // grid = try Grid.init(n_rows, n_rows * window_ratio);
    // grid.fillZeros();
    // grid.set(1, 1, .Building);
    // grid.set(1, 2, .Building);
    // grid.set(1, 3, .Building);

    cell_size = 50;
    player = Vec2.init(@intToFloat(f32, grid.cols) / 2.0, @intToFloat(f32, grid.rows) / 2.0).scale(cell_size);
    player_size = cell_size * 0.9;
}

pub fn view() Mat4 {
    return Mat4.translation2d(camera.sub(Vec2.init(window_width / 2, window_height / 2)).neg());
}

pub fn collide(position: Vec2) bool {
    const p = position.add(Vec2.init(player_size / 2, player_size / 2));
    const x = @floatToInt(u32, p.x / cell_size);
    const y = @floatToInt(u32, p.y / cell_size);
    if (!grid.inBounds(x, y) or grid.at(x, y) != .Dirt) {
        return true;
    }
    return false;
}

const cells_per_second = 7;

pub fn update(dt: f32) !void {
    const vel = if (player_velocity.norm() > 0) player_velocity.normalize() else player_velocity;
    const player1 = player.add(vel.scale(dt * cells_per_second * cell_size));

    if (!collide(player1)) {
        player = player1;
    }

    camera = player;
}
