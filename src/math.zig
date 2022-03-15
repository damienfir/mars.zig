const std = @import("std");

pub const Vec2 = packed struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return Vec2{ .x = x, .y = y };
    }

    pub fn fromU32(x: u32, y: u32) Vec2 {
        return Vec2{ .x = @intToFloat(f32, x), .y = @intToFloat(f32, y) };
    }

    pub fn div(v: Vec2, a: f32) Vec2 {
        return Vec2.init(v.x / a, v.y / a);
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return Vec2.init(a.x + b.x, a.y + b.y);
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return Vec2.init(a.x - b.x, a.y - b.y);
    }

    pub fn mul(a: Vec2, b: Vec2) Vec2 {
        return Vec2.init(a.x * b.x, a.y * b.y);
    }

    pub fn scale(a: Vec2, f: f32) Vec2 {
        return Vec2.init(a.x * f, a.y * f);
    }

    pub fn norm(v: Vec2) f32 {
        return @sqrt(v.x * v.x + v.y * v.y);
    }

    pub fn normalize(v: Vec2) Vec2 {
        return v.div(norm(v));
    }

    pub fn neg(v: Vec2) Vec2 {
        return Vec2{ .x = -v.x, .y = -v.y };
    }

    pub fn eq(a: Vec2, b: Vec2) bool {
        return a.x == b.x and a.y == b.y;
    }
};

pub const Vec3 = packed struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }

    pub fn div(v: Vec3, a: f32) Vec3 {
        return Vec3.init(v.x / a, v.y / a, v.z / a);
    }

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return Vec3.init(a.x + b.x, a.y + b.y, a.z + b.z);
    }

    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return Vec3.init(a.x - b.x, a.y - b.y, a.z - b.z);
    }

    pub fn scale(a: Vec3, f: f32) Vec3 {
        return Vec3.init(a.x * f, a.y * f, a.z * f);
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return Vec3.init(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
    }

    pub fn norm(v: Vec3) f32 {
        return @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    }

    pub fn normalize(v: Vec3) Vec3 {
        return div(v, norm(v));
    }

    pub fn eq(a: Vec3, b: Vec3) bool {
        return a.x == b.x and a.y == b.y and a.z == b.z;
    }
};

test "cross" {
    const v = Vec3.init(1, 0, 0).cross(Vec3.init(0, 1, 0));
    try std.testing.expect(v.x == 0);
    try std.testing.expect(v.y == 0);
    try std.testing.expect(v.z == 1);
}

test "vec normalize" {
    const v = Vec3.init(2, 0, 0).normalize();
    try std.testing.expect(v.x == 1);
    try std.testing.expect(v.y == 0);
    try std.testing.expect(v.z == 0);
}

pub const Mat4 = struct {
    data: [16]f32,

    pub fn set(m: *Mat4, i: u4, j: u4, value: f32) void {
        m.data[i * 4 + j] = value;
    }

    pub fn get(m: *Mat4, i: u4, j: u4) f32 {
        return m.data[i * 4 + j];
    }

    pub fn zero() Mat4 {
        var data = [_]f32{0} ** 16;
        return Mat4{ .data = data };
    }

    pub fn eye() Mat4 {
        var mat = Mat4.zero();
        mat.data[0] = 1;
        mat.data[5] = 1;
        mat.data[10] = 1;
        mat.data[15] = 1;
        return mat;
    }

    pub fn perpective(near: f32, far: f32, right: f32, top: f32) Mat4 {
        var mat = Mat4.zero();
        mat.data[0] = near / right;
        mat.data[5] = near / top;
        mat.data[10] = -(far + near) / (far - near);
        mat.data[11] = -2 * far * near / (far - near);
        mat.data[14] = -1;
        return mat;
    }

    pub fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
        var m = Mat4.zero();
        m.set(0, 0, 2 / (right - left));
        m.set(1, 1, 2 / (top - bottom));
        m.set(2, 2, -2 / (far - near));
        m.set(0, 3, -(right + left) / (right - left));
        m.set(1, 3, -(top + bottom) / (top - bottom));
        m.set(2, 3, -(far + near) / (far - near));
        m.set(3, 3, 1);
        return m;
    }

    pub fn lookat(position: Vec3, target: Vec3, up: Vec3) Mat4 {
        const direction = position.sub(target).normalize();
        const right = up.cross(direction).normalize();
        const cam_up = direction.cross(right);

        var rot = Mat4.zero();
        rot.data[0] = right.x;
        rot.data[1] = right.y;
        rot.data[2] = right.z;
        rot.data[4] = cam_up.x;
        rot.data[5] = cam_up.y;
        rot.data[6] = cam_up.z;
        rot.data[8] = direction.x;
        rot.data[9] = direction.y;
        rot.data[10] = direction.z;
        rot.data[15] = 1;

        var trans = Mat4.eye();
        trans.data[3] = -position.x;
        trans.data[7] = -position.y;
        trans.data[11] = -position.z;

        return mul(rot, trans);
    }

    pub fn translate(t: Vec3) Mat4 {
        var m = Mat4.eye();
        m.data[3] = t.x;
        m.data[7] = t.y;
        m.data[11] = t.z;
        return m;
    }

    pub fn print(self: Mat4) void {
        std.debug.print("{d:.2} {d:.2} {d:.2} {d:.2}\n", .{ self.data[0], self.data[1], self.data[2], self.data[3] });
        std.debug.print("{d:.2} {d:.2} {d:.2} {d:.2}\n", .{ self.data[4], self.data[5], self.data[6], self.data[7] });
        std.debug.print("{d:.2} {d:.2} {d:.2} {d:.2}\n", .{ self.data[8], self.data[9], self.data[10], self.data[11] });
        std.debug.print("{d:.2} {d:.2} {d:.2} {d:.2}\n", .{ self.data[12], self.data[13], self.data[14], self.data[15] });
    }

    pub fn mul(A: Mat4, B: Mat4) Mat4 {
        const a = &A.data;
        const b = &B.data;
        var C = Mat4{ .data = undefined };
        var d = &C.data;
        d[0] = a[0] * b[0] + a[1] * b[4] + a[2] * b[8] + a[3] * b[12];
        d[1] = a[0] * b[1] + a[1] * b[5] + a[2] * b[9] + a[3] * b[13];
        d[2] = a[0] * b[2] + a[1] * b[6] + a[2] * b[10] + a[3] * b[14];
        d[3] = a[0] * b[3] + a[1] * b[7] + a[2] * b[11] + a[3] * b[15];

        d[4] = a[4] * b[0] + a[5] * b[4] + a[6] * b[8] + a[7] * b[12];
        d[5] = a[4] * b[1] + a[5] * b[5] + a[6] * b[9] + a[7] * b[13];
        d[6] = a[4] * b[2] + a[5] * b[6] + a[6] * b[10] + a[7] * b[14];
        d[7] = a[4] * b[3] + a[5] * b[7] + a[6] * b[11] + a[7] * b[15];

        d[8] = a[8] * b[0] + a[9] * b[4] + a[10] * b[8] + a[11] * b[12];
        d[9] = a[8] * b[1] + a[9] * b[5] + a[10] * b[9] + a[11] * b[13];
        d[10] = a[8] * b[2] + a[9] * b[6] + a[10] * b[10] + a[11] * b[14];
        d[11] = a[8] * b[3] + a[9] * b[7] + a[10] * b[11] + a[11] * b[15];

        d[12] = a[12] * b[0] + a[13] * b[4] + a[14] * b[8] + a[15] * b[12];
        d[13] = a[12] * b[1] + a[13] * b[5] + a[14] * b[9] + a[15] * b[13];
        d[14] = a[12] * b[2] + a[13] * b[6] + a[14] * b[10] + a[15] * b[14];
        d[15] = a[12] * b[3] + a[13] * b[7] + a[14] * b[11] + a[15] * b[15];

        return C;
    }

    pub fn mulvec3(M: Mat4, v: Vec3) Vec3 {
        const x = M.data[0] * v.x + M.data[1] * v.y + M.data[2] * v.z + M.data[3];
        const y = M.data[4] * v.x + M.data[5] * v.y + M.data[6] * v.z + M.data[7];
        const z = M.data[8] * v.x + M.data[9] * v.y + M.data[10] * v.z + M.data[11];
        return Vec3.init(x, y, z);
    }

    pub fn rotation_y(rot: f32) Mat4 {
        var m = Mat4.eye();
        m.data[0] = @cos(rot);
        m.data[2] = -@sin(rot);
        m.data[8] = @sin(rot);
        m.data[10] = @cos(rot);
        return m;
    }

    pub fn translation(v: Vec3) Mat4 {
        var m = Mat4.eye();
        m.data[3] = v.x;
        m.data[7] = v.y;
        m.data[11] = v.z;
        return m;
    }

    pub fn translation2d(v: Vec2) Mat4 {
        var m = Mat4.eye();
        m.data[3] = v.x;
        m.data[7] = v.y;
        return m;
    }

    pub fn scale(s: f32) Mat4 {
        var m = Mat4.eye();
        m.set(0, 0, s);
        m.set(1, 1, s);
        m.set(2, 2, s);
        m.set(3, 3, s);
        return m;
    }
};

test "matrix multiplication" {
    var A = Mat4.eye();
    var B = Mat4.eye();
    B.data[0] = 2;
    const C = A.mul(B);
    try std.testing.expect(C.data[0] == 2);
}

pub const Point = struct {
    i: u32,
    j: u32,

    pub fn eq(self: Point, other: Point) bool {
        return self.i == other.i and self.j == other.j;
    }
};
