const std = @import("std");

const audio = @import("audio.zig");
const renderer = @import("renderer.zig");
const ui = @import("ui.zig");
const sequencer = @import("sequencer.zig");
const Vec2i = renderer.Vec2i;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var gpa_allocator = gpa.allocator();

pub fn main() !void {
    // Deinitialize the gpa on exit
    defer _ = gpa.deinit();

    // Initialize the systems
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
    var is_mouse_down = false;

    // Test UI state
    var filter_frequency: f32 = 440.0;
    var attack_time: f32 = 0.1;

    // Setup the sequencer
    try sequencer.init();
    defer sequencer.deinit();

    // While we're still rendering...
    while (running) {
        // Calculate the delta time
        last_frame = current_frame;
        current_frame = renderer.now();
        var delta = renderer.getDeltaTime(current_frame, last_frame);

        // Mouse state
        var is_mouse_clicked: bool = false;

        // Handle events
        for (try renderer.events()) |event| {
            switch (event) {
                .quit => running = false,
                .mouse_down => {
                    is_mouse_down = true;
                    is_mouse_clicked = true;
                },
                .mouse_up => {
                    is_mouse_down = false;
                    is_mouse_clicked = false;
                },
                .mouse_motion => |mouse_motion| {
                    mouse_position = .{ .x = mouse_motion.x, .y = mouse_motion.y };
                },
            }
        }

        // Update the UI state
        ui.update(mouse_position, is_mouse_down, is_mouse_clicked, delta);
        // Update the sequencer
        sequencer.update();

        // Draw the UI
        try renderer.clear(clear_color);

        // Draw the filter control
        const normalized_frequency = filter_frequency / 4000.0;
        const slider_color: u8 = @intFromFloat(150 + (normalized_frequency * 105));
        try ui.slider(&filter_frequency, .{
            .min = 60.0,
            .max = 4000.0,
            .pos = .{ .x = 16, .y = 16 },
            .colors = .{ .foreground = .{ .r = slider_color, .g = slider_color, .b = slider_color } },
        });
        audio.setFilterFrequency(filter_frequency);

        // Draw the attack control
        try ui.slider(&attack_time, .{
            .min = 0.001,
            .max = 0.5,
            .pos = .{ .x = 32 + 128, .y = 16 },
            .colors = .{ .foreground = .{ .r = @intFromFloat(64 + (attack_time * 255 - 64)), .g = 128, .b = 255 } },
        });
        audio.setAttackTime(attack_time);

        // Draw the sequencer
        try sequencer.draw(.{ .x = 16, .y = 48 });

        // Present the frame
        renderer.present();

        // Keep up a steady 60 FPS
        std.time.sleep(32 * 1_000_000);
    }
}
