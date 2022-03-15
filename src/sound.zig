const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_mixer.h");
});

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator;

pub const SoundName = enum {
    Teleportation,
};

fn soundForName(sound: SoundName) []const u8 {
    return switch (sound) {
        .Teleportation => "res/teleportation.wav",
    };
}

const SdlMixChunk = *c.Mix_Chunk;

var sound_cache = std.AutoHashMap(SoundName, SdlMixChunk).init(allocator());

fn getSound(sound: SoundName) !SdlMixChunk {
    return sound_cache.get(sound) orelse {
        const s = c.Mix_LoadWAV(soundForName(sound).ptr);

        if (s == null) {
            std.debug.print("Error: {s}\n", .{c.SDL_GetError()});
            return SdlError.LoadFileError;
        }

        try sound_cache.put(sound, s);

        return s;
    };
}

const SdlError = error{
    SdlInitFailed,
    MixerInitFailed,
    LoadFileError,
    PlayFileError,
};

pub fn init_sdl() !void {
    if (c.SDL_Init(c.SDL_INIT_AUDIO) < 0) {
        std.debug.print("SDL could not be initialized. SDL_Error: {s}\n", .{c.SDL_GetError()});
        return SdlError.SdlInitFailed;
    }

    if (c.Mix_OpenAudio(22050, c.MIX_DEFAULT_FORMAT, 2, 1024) == -1) {
        std.debug.print("SDL2_mixer could not be initialized. SDL_Error: {s}\n", .{c.SDL_GetError()});
        return SdlError.MixerInitFailed;
    }
}

pub fn deinit_sdl() void {
    var it = sound_cache.valueIterator();
    while (it.next()) |entry| {
        c.Mix_FreeChunk(entry.*);
    }
    sound_cache.deinit();

    c.Mix_CloseAudio();
    c.SDL_Quit();
}

pub fn play(sound: SoundName) void {
    playSound(sound) catch unreachable;
}

fn playSound(sound: SoundName) !void {
    const buffer = try getSound(sound);

    const channel = c.Mix_PlayChannel(-1, buffer, 0);
    if (channel == -1) {
        std.debug.print("Error: {s}\n", .{c.SDL_GetError()});
        return SdlError.PlayFileError;
    }
}

