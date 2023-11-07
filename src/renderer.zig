const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_audio.h");
});

var allocator: std.mem.Allocator = undefined;
var events_arena: std.heap.ArenaAllocator = undefined;

var window: ?*c.SDL_Window = null;
var _renderer: ?*c.SDL_Renderer = null;

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
};

pub fn init(_allocator: std.mem.Allocator) !void {
    allocator = _allocator;
    events_arena = std.heap.ArenaAllocator.init(allocator);

    std.log.debug("Initializing the renderer", .{});

    std.log.debug("Initializing SDL video subsystem", .{});
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        return error.SDLInitFailed;
    }

    std.log.debug("Creating SDL_Window", .{});
    window = c.SDL_CreateWindow(
        "<::- podpad -::>",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        408,
        408,
        c.SDL_WINDOW_SHOWN,
    );
    if (window == null) {
        std.log.err("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    }

    std.log.debug("Creating SDL_Renderer", .{});
    _renderer = c.SDL_CreateRenderer(
        window,
        -1,
        c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
    );
    if (_renderer == null) {
        std.log.err("SDL_CreateRenderer failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateRendererFailed;
    }

    std.log.debug("Intiialized renderer", .{});
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
                        else => unreachable,
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
                        else => unreachable,
                    },
                } });
            },
            else => {},
        }
    }

    // Return the items from the array list.
    return _events.items;
}

pub fn deinit() void {
    std.log.debug("Destroying renderer", .{});
    c.SDL_DestroyRenderer(_renderer);
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
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

pub fn now() u64 {
    return c.SDL_GetPerformanceCounter();
}

pub fn getDeltaTime(start: u64, end: u64) f32 {
    var frequency = c.SDL_GetPerformanceFrequency();
    return @as(f32, @floatFromInt(start - end)) * 1000 / @as(f32, @floatFromInt(frequency));
}
