//!
//! # The rendering system for podpad.
//!
//! This module is responsible for rendering the game to the screen.
//!
//! It uses SDL2 to render the application.
//!
const std = @import("std");
const c = @cImport({
    // Include SDL2 headers.
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_audio.h");

    // Include Freetype headers.
    @cInclude("freetype/freetype.h");
});

const renderer_log = std.log.scoped(.renderer);

pub const Timer = packed struct {
    start: u64 = 0,
    end: u64 = 0,

    pub fn start() void {
        start = now();
    }
};

pub const Color = packed struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,
};

pub const Rect = packed struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,
};

pub const Vec2i = packed struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const KeyCode = enum(c_int) {
    c = c.SDLK_c,
    r = c.SDLK_r,
    space = c.SDLK_SPACE,
    left = c.SDLK_LEFT,

    pub fn fromSDLKey(key: c.SDL_Keycode) ?KeyCode {
        return switch (key) {
            c.SDLK_c => .c,
            c.SDLK_r => .r,
            c.SDLK_SPACE => .space,
            c.SDLK_LEFT => .left,
            else => null,
        };
    }
};

// Create struct that uses each SDL_Scancode as a field.
const WindowEvent = union(enum) {
    quit,
    mouse_motion: struct {
        x: i32,
        y: i32,
    },
    mouse_down: struct {
        x: i32,
        y: i32,
        button: enum {
            left,
            middle,
            right,
        },
    },
    mouse_up: struct {
        x: i32,
        y: i32,
        button: enum {
            left,
            middle,
            right,
        },
    },
    keydown: struct {
        code: KeyCode,
    },
    keyup: struct {
        code: KeyCode,
    },
};

/// A Freetype font.
pub const Font = struct {
    const Self = @This();

    face: c.FT_Face = undefined,
    glyphs: std.AutoHashMap(u64, c.FT_GlyphSlot),
    size: u32 = 11,

    pub fn init(path: []const u8) !Self {
        var self: Self = .{
            .glyphs = std.AutoHashMap(u64, c.FT_GlyphSlot).init(allocator),
        };

        if (c.FT_New_Face(ft2_lib, @ptrCast(path), 0, &self.face) != 0) {
            return error.FTNewFaceFailed;
        }
        if (c.FT_Set_Pixel_Sizes(self.face, 0, 11) != 0) {
            return error.FTSetPixelSizesFailed;
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (c.FT_Done_Face(self.face) != 0) {
            renderer_log.err("FT_Done_Face failed: {s}\n", .{c.SDL_GetError()});
        }
        self.glyphs.deinit();
    }

    pub fn setSize(self: *const Self, size: u32) !void {
        if (c.FT_Set_Pixel_Sizes(self.face, 0, size) != 0) {
            return error.FTSetPixelSizesFailed;
        }
        self.size = size;
    }

    pub fn getGlyph(self: *Self, codepoint: u32) !c.FT_GlyphSlot {
        var found = self.glyphs.get(@as(u64, codepoint));
        if (found != null) {
            return found.?;
        }

        if (c.FT_Load_Char(self.face, codepoint, c.FT_LOAD_RENDER) != 0) {
            return error.FTLoadCharFailed;
        }

        var glyph = self.face.*.glyph;
        try self.glyphs.put(@as(u64, codepoint), glyph);
        return glyph;
    }
};

/// Font library.
pub const Fonts = struct {
    const Self = @This();

    fonts: std.StringHashMap(Font),

    pub fn init() !Self {
        if (c.FT_Init_FreeType(&ft2_lib) != 0) {
            return error.FTInitFailed;
        }

        return .{ .fonts = std.StringHashMap(Font).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        // Free each font.
        var iter = self.fonts.valueIterator();
        while (iter.next()) |font| {
            font.deinit();
        }

        // Deinitialize the hashmap.
        self.fonts.deinit();

        // Deinitialize the font library.
        if (c.FT_Done_FreeType(ft2_lib) != 0) {
            renderer_log.err("FT_Done_FreeType failed: {s}\n", .{c.SDL_GetError()});
        }
    }

    pub fn load(self: *Self, name: []const u8, path: []const u8) !Font {
        var font = try Font.init(path);
        try self.fonts.put(name, font);
        return font;
    }

    pub fn get(self: *const Self, name: []const u8) !Font {
        var found = self.fonts.get(name);
        if (found != null) {
            return found.?;
        }

        return error.FontNotFound;
    }
};

var allocator: std.mem.Allocator = undefined;
var events_arena: std.heap.ArenaAllocator = undefined;

var window: ?*c.SDL_Window = null;
var _renderer: ?*c.SDL_Renderer = null;
var ft2_lib: c.FT_Library = undefined;
var fonts: Fonts = undefined;

pub fn init(_allocator: std.mem.Allocator) !void {
    allocator = _allocator;
    events_arena = std.heap.ArenaAllocator.init(allocator);

    renderer_log.debug("Initializing fonts", .{});
    fonts = try Fonts.init();

    renderer_log.debug("Loading fonts", .{});
    _ = try fonts.load("default", "assets/fonts/pixeled.ttf");

    renderer_log.debug("Initializing the renderer", .{});

    renderer_log.debug("Initializing SDL video subsystem", .{});
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        return error.SDLInitFailed;
    }

    renderer_log.debug("Creating SDL_Window", .{});
    window = c.SDL_CreateWindow(
        "<::- podpad -::>",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        408,
        408 + 32,
        c.SDL_WINDOW_SHOWN,
    );
    if (window == null) {
        renderer_log.err("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    }

    renderer_log.debug("Creating SDL_Renderer", .{});
    _renderer = c.SDL_CreateRenderer(
        window,
        -1,
        c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
    );
    if (_renderer == null) {
        renderer_log.err("SDL_CreateRenderer failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateRendererFailed;
    }

    renderer_log.debug("Intiialized renderer", .{});
}

pub fn deinit() void {
    renderer_log.debug("Destroying renderer", .{});
    events_arena.deinit();

    // Destroy the font library.
    defer fonts.deinit();

    // Destroy the renderer and window.
    c.SDL_DestroyRenderer(_renderer);
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

pub fn events() ![]WindowEvent {
    // Reset the arena to retain capacity.
    _ = events_arena.reset(.retain_capacity);

    // Allocate the events array on the arena.
    var _events = try std.ArrayList(WindowEvent).initCapacity(
        events_arena.allocator(),
        32,
    );

    // Poll for events.
    var event = c.SDL_Event{ .type = 0 };
    while (c.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            c.SDL_QUIT => {
                try _events.append(.quit);
            },
            c.SDL_MOUSEMOTION => {
                var motion = event.motion;
                try _events.append(.{ .mouse_motion = .{
                    .x = motion.x,
                    .y = motion.y,
                } });
            },
            c.SDL_MOUSEBUTTONDOWN => {
                var button = event.button;
                try _events.append(.{ .mouse_down = .{
                    .x = button.x,
                    .y = button.y,
                    .button = switch (button.button) {
                        c.SDL_BUTTON_LEFT => .left,
                        c.SDL_BUTTON_MIDDLE => .middle,
                        c.SDL_BUTTON_RIGHT => .right,
                        else => continue,
                    },
                } });
            },
            c.SDL_MOUSEBUTTONUP => {
                var button = event.button;
                try _events.append(.{ .mouse_up = .{
                    .x = button.x,
                    .y = button.y,
                    .button = switch (button.button) {
                        c.SDL_BUTTON_LEFT => .left,
                        c.SDL_BUTTON_MIDDLE => .middle,
                        c.SDL_BUTTON_RIGHT => .right,
                        else => continue,
                    },
                } });
            },
            c.SDL_KEYDOWN => {
                var key = event.key;
                try _events.append(.{
                    .keydown = .{
                        .code = KeyCode.fromSDLKey(key.keysym.sym) orelse continue,
                    },
                });
            },
            c.SDL_KEYUP => {
                var key = event.key;
                try _events.append(.{
                    .keyup = .{
                        .code = KeyCode.fromSDLKey(key.keysym.sym) orelse continue,
                    },
                });
            },
            else => {},
        }
    }

    // Return the items from the array list.
    return _events.items;
}

pub fn clear(color: Color) !void {
    if (c.SDL_SetRenderDrawColor(_renderer, color.r, color.g, color.b, 255) != 0) {
        return error.SDLSetRenderDrawColorFailed;
    }
    if (c.SDL_RenderClear(_renderer) != 0) {
        return error.SDLRenderClearFailed;
    }
}

pub fn present() void {
    c.SDL_RenderPresent(_renderer);
}

pub fn drawRect(rect: Rect, color: Color) !void {
    if (c.SDL_SetRenderDrawColor(_renderer, color.r, color.g, color.b, color.a) != 0) {
        return error.SDLSetRenderDrawColorFailed;
    }
    var _rect = c.SDL_Rect{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
    if (c.SDL_RenderFillRect(_renderer, &_rect) != 0) {
        return error.SDLRenderFillRectFailed;
    }
}

// pub fn drawText(name: []const u8, text: []const u8, pos: Vec2i, color: Color) !void {
//     // ... FIll this in for me!
// }

pub fn drawText(name: []const u8, text: []const u8, pos: Vec2i, color: Color) !void {
    var font = try fonts.get(name);
    var x = pos.x;
    var y = pos.y;

    var pen = c.FT_Vector{ .x = 0, .y = 0 };
    var prev_glyph: ?c.FT_GlyphSlot = null;

    for (text) |codepoint| {
        var glyph = try font.getGlyph(codepoint);
        if (c.FT_Load_Char(font.face, codepoint, c.FT_LOAD_RENDER) != 0) {
            return error.FTLoadCharFailed;
        }

        var bitmap = glyph.*.bitmap;
        var bitmap_left = glyph.*.bitmap_left;
        var bitmap_top = glyph.*.bitmap_top;

        var x_offset = pen.x + bitmap_left;
        var y_offset = pen.y - bitmap_top;

        var rect = Rect{
            .x = @as(i32, @intCast(x + x_offset)),
            .y = @as(i32, @intCast(y - y_offset)),
            .w = @as(i32, @intCast(bitmap.width)),
            .h = @as(i32, @intCast(bitmap.rows)),
        };
        var _rect = c.SDL_Rect{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };

        // Create a texture for the glyph
        var texture = c.SDL_CreateTexture(
            _renderer,
            c.SDL_PIXELFORMAT_ABGR8888,
            c.SDL_TEXTUREACCESS_STATIC,
            @intCast(bitmap.width),
            @intCast(bitmap.rows),
        );
        defer c.SDL_DestroyTexture(texture);

        if (texture == null) {
            return error.SDLCreateTextureFailed;
        }

        // Set the texture's color
        if (c.SDL_SetTextureColorMod(texture, color.r, color.g, color.b) != 0) {
            return error.SDLSetTextureColorModFailed;
        }

        // Update the texture with the glyph's bitmap
        if (c.SDL_UpdateTexture(texture, null, bitmap.buffer, bitmap.pitch) != 0) {
            return error.SDLUpdateTextureFailed;
        }

        // Copy the texture to the renderer
        if (c.SDL_RenderCopy(_renderer, texture, null, &_rect) != 0) {
            return error.SDLRenderCopyFailed;
        }

        // Advance the pen position
        pen.x += glyph.*.advance.x >> 6; // Convert from 26.6 fixed-point to integer
        pen.y += glyph.*.advance.y >> 6; // Convert from 26.6 fixed-point to integer

        prev_glyph = glyph;
    }
}

pub fn now() u64 {
    return c.SDL_GetPerformanceCounter();
}

pub fn getDeltaTime(start: u64, end: u64) f32 {
    var frequency = c.SDL_GetPerformanceFrequency();
    return @as(f32, @floatFromInt(start - end)) * 1000 / @as(f32, @floatFromInt(frequency));
}
