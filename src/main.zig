const std = @import("std");

const audio = @import("audio.zig");
const renderer = @import("renderer.zig");
const ui = @import("ui.zig");
const Vec2i = renderer.Vec2i;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var gpa_allocator = gpa.allocator();

pub fn main() !void {
    // Setup the systems
    try renderer.init(gpa_allocator);
    defer renderer.deinit();

    try audio.init(gpa_allocator);
    defer audio.deinit();

    try ui.init(gpa_allocator);
    defer ui.deinit();

    // Create some application state
    var mouse_position: Vec2i = .{ .x = 0, .y = 0 };
    var clear_color = .{ .r = 0, .g = 0, .b = 0 };
    var running = true;
    var current_frame: u64 = 0;
    var last_frame: u64 = 0;

    // While we're still rendering...
    while (running) {
        // Calculate the delta time
        last_frame = current_frame;
        current_frame = renderer.now();
        var delta = renderer.getDeltaTime(current_frame, last_frame);

        // Mouse state
        var is_mouse_down: bool = false;

        // Handle events
        for (try renderer.events()) |event| {
            switch (event) {
                .quit => running = false,
                .mouse_down => {
                    is_mouse_down = true;
                },
                .mouse_up => {
                    is_mouse_down = false;
                },
                .mouse_motion => |mouse_motion| {
                    mouse_position = .{ .x = mouse_motion.x, .y = mouse_motion.y };
                },
            }
        }

        // Update the UI
        try ui.update(mouse_position, is_mouse_down, delta);

        // Draw the UI
        try renderer.clear(clear_color);
        try ui.render();
        renderer.present();

        // Keep up a steady 60 FPS
        std.time.sleep(32 * 1_000_000);
    }
}
