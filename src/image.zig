const std = @import("std");
const c = @cImport({
    @cDefine("STB_IMAGE_IMPLEMENTATION", {});
    @cDefine("STBI_ONLY_PNG", {});
    @cInclude("stb_image.h");
});

const allocator = @import("game.zig").allocator;

pub const Image = struct {
    width: u32,
    height: u32,
    channels: u32,
    data: []u8,
    from_stb: bool = false,

    pub fn deinit(im: Image) void {
        if (im.from_stb) {
            c.stbi_image_free(im.data.ptr);
        } else {
            allocator.free(im.data);
        }
    }

    pub fn cropCopy(im: Image, cr: Rect) !Image {
        const width = cr.x1 - cr.x0;
        const height = cr.y1 - cr.y0;
        var cropped = Image{
            .width = width,
            .height = height,
            .channels = im.channels,
            .data = try allocator.alloc(u8, width * height * im.channels),
        };

        var i: u32 = 0;
        while (i < height) : (i += 1) {
            var j: u32 = 0;
            while (j < width) : (j += 1) {
                var chan: u32 = 0;
                while (chan < im.channels) : (chan += 1) {
                    cropped.data[i * cropped.width * cropped.channels + j * cropped.channels + chan] = im.data[(i + cr.y0) * im.width * im.channels + (j + cr.x0) * im.channels + chan];
                }
            }
        }

        return cropped;
    }
};

pub const Rect = struct {
    x0: u32,
    y0: u32,
    x1: u32,
    y1: u32,
};

const ImageError = error{
    FailToLoad,
};

pub fn load(path: []const u8) !Image {
    var image: Image = undefined;
    const ptr = c.stbi_load(
        path.ptr,
        @ptrCast(*c_int, &image.width),
        @ptrCast(*c_int, &image.height),
        @ptrCast(*c_int, &image.channels),
        0,
    );

    if (ptr == null) {
        return ImageError.FailToLoad;
    }

    image.from_stb = true;
    image.data.ptr = ptr;
    image.data.len = image.width * image.height * image.channels;

    return image;
}
