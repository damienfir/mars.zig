const std = @import("std");
const c = @cImport({
    @cDefine("STB_IMAGE_IMPLEMENTATION", {});
    @cDefine("STBI_ONLY_PNG", {});
    @cInclude("stb_image.h");
});

pub const Image = struct {
    width: u32,
    height: u32,
    channels: u32,
    data: []u8,

    pub fn deinit(im: Image) void {
        c.stbi_image_free(im.data.ptr);
    }
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

    image.data.ptr = ptr;
    image.data.len = image.width * image.height * image.channels;

    return image;
}
