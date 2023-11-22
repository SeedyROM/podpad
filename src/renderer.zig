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

pub const Glyph = struct {
    const Self = @This();

    texture: ?*c.SDL_Texture = null,
    rect: Rect = undefined,
    advance: Vec2i = undefined,

    pub fn fromCodepoint(font: *Font, codepoint: u32, color: Color) !Self {
        if (c.FT_Load_Char(font.face, codepoint, c.FT_LOAD_RENDER) != 0) {
            return error.FTLoadCharFailed;
        }

        var bitmap = font.face.*.glyph.*.bitmap;

        var rect = Rect{
            .x = 0,
            .y = 0,
            .w = @as(i32, @intCast(bitmap.width)),
            .h = @as(i32, @intCast(bitmap.rows)),
        };

        var texture = c.SDL_CreateTexture(
            _renderer,
            c.SDL_PIXELFORMAT_RGBA8888,
            c.SDL_TEXTUREACCESS_STREAMING,
            @intCast(bitmap.width),
            @intCast(bitmap.rows),
        );

        if (texture == null) {
            return error.SDLCreateTextureFailed;
        }

        // convert the glyph's bitmap to RGBA
        // this needs to be cached with the glyph
        var rgba = try std.ArrayList(u8).initCapacity(allocator, bitmap.width * bitmap.rows * 4);
        defer rgba.deinit();
        for (bitmap.buffer[0 .. bitmap.width * bitmap.rows]) |pixel| {
            try rgba.append(pixel);
            try rgba.append(pixel);
            try rgba.append(pixel);
            try rgba.append(255);
        }

        // Set the texture's color
        if (c.SDL_SetTextureColorMod(texture, color.r, color.g, color.b) != 0) {
            return error.SDLSetTextureColorModFailed;
        }

        // Update the texture with the glyph's bitmap
        if (c.SDL_UpdateTexture(texture, null, @ptrCast(rgba.items), @intCast(bitmap.width * 4)) != 0) {
            return error.SDLUpdateTextureFailed;
        }

        // Set the texture blend mode
        if (c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND) != 0) {
            return error.SDLSetTextureBlendModeFailed;
        }

        return .{
            .texture = texture,
            .rect = rect,
            .advance = Vec2i{
                .x = @as(i32, @intCast(font.face.*.glyph.*.advance.x)),
                .y = @as(i32, @intCast(font.face.*.glyph.*.advance.y)),
            },
        };
    }

    pub fn deinit(self: *Self) void {
        c.SDL_DestroyTexture(self.texture);
    }
};

/// A Freetype font.
pub const Font = struct {
    const Self = @This();

    face: c.FT_Face = undefined,
    glyphs: std.AutoHashMap(u64, Glyph),
    size: u32 = 10,

    pub fn init(path: []const u8) !Self {
        var self: Self = .{
            .glyphs = std.AutoHashMap(u64, Glyph).init(allocator),
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

        var glyphs_iter = self.glyphs.valueIterator();
        while (glyphs_iter.next()) |glyph| {
            glyph.deinit();
        }

        self.glyphs.deinit();
    }

    pub fn setSize(self: *Self, size: u32) !void {
        if (c.FT_Set_Pixel_Sizes(self.face, 0, size) != 0) {
            return error.FTSetPixelSizesFailed;
        }
        self.size = size;
    }

    pub fn getGlyph(self: *Self, codepoint: u32, color: Color) !Glyph {
        var glyph = self.glyphs.get(codepoint);
        if (glyph != null) {
            return glyph.?;
        }

        var new_glyph = try Glyph.fromCodepoint(self, codepoint, color);
        try self.glyphs.put(codepoint, new_glyph);
        return new_glyph;
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
var glyphs: std.ArrayList(Glyph) = undefined;

pub fn init(_allocator: std.mem.Allocator, width: u32, height: u32) !void {
    allocator = _allocator;
    events_arena = std.heap.ArenaAllocator.init(allocator);
    glyphs = try std.ArrayList(Glyph).initCapacity(allocator, 128);

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
        @intCast(width),
        @intCast(height),
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

pub fn drawText(name: []const u8, text: []const u8, pos: Vec2i, color: Color) !void {
    var font = try fonts.get(name);
    var pen = c.FT_Vector{ .x = pos.x, .y = pos.y };
    var prev_glyph: ?Glyph = null;

    // Clear the glyphs array list.
    glyphs.clearRetainingCapacity();

    // Step 1: Calculate the maximum glyph height
    var max_height: i32 = 0;
    for (text) |codepoint| {
        var glyph = try font.getGlyph(codepoint, color);

        try glyphs.append(glyph);

        if (glyph.rect.h > max_height) {
            max_height = glyph.rect.h;
        }
    }

    // Step 2: Render each glyph
    for (glyphs.items) |glyph| {
        var _rect = c.SDL_Rect{
            .x = @intCast(pen.x + glyph.rect.x),
            .y = @intCast(pen.y + (max_height - glyph.rect.y)),
            .w = @intCast(glyph.rect.w),
            .h = @intCast(glyph.rect.h),
        };

        if (c.SDL_RenderCopy(_renderer, glyph.texture, null, &_rect) != 0) {
            return error.SDLRenderCopyFailed;
        }

        pen.x += @as(i32, @intCast(glyph.advance.x)) >> 6;
        pen.y += @as(i32, @intCast(glyph.advance.y)) >> 6;

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
