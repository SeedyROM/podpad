const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var gpaallocator = gpa.allocator();

pub fn main() !void {
    try renderer.init(gpaallocator);
    defer renderer.deinit();

    var running = true;
    while (running) {
        for (try renderer.events()) |event| {
            switch (event) {
                .quit => running = false,
            }
        }

        try renderer.clear(127, 63, 255);
        renderer.present();

        std.time.sleep(60 * 1_000_000);
    }
}

const renderer = struct {
    const c = @cImport({
        @cInclude("SDL2/SDL.h");
    });

    var allocator: std.mem.Allocator = undefined;
    var events_arena: std.heap.ArenaAllocator = undefined;

    var window: ?*c.SDL_Window = null;
    var _renderer: ?*c.SDL_Renderer = null;

    const WindowEvent = union(enum(c_int)) {
        quit,
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
            600,
            600,
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

    pub fn clear(r: u8, g: u8, b: u8) !void {
        if (c.SDL_SetRenderDrawColor(_renderer, r, g, b, 255) != 0) {
            return error.SDLSetRenderDrawColorFailed;
        }
        if (c.SDL_RenderClear(_renderer) != 0) {
            return error.SDLRenderClearFailed;
        }
    }

    pub fn present() void {
        c.SDL_RenderPresent(_renderer);
    }
};
