//!
//! # `podpad` is a simple syntheizer/sequencer!
//!
const std = @import("std");
const builtin = @import("builtin");

const audio = @import("audio.zig");
const renderer = @import("renderer.zig");
const ui = @import("ui.zig");
const sequencer = @import("ui/sequencer.zig");

const Vec2i = renderer.Vec2i;

// Create the GPA allocator for the debug build
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
// Use the GPA for debug builds and the C allocator for release builds
const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.c_allocator;

pub fn main() !void {
    // Debug memory leaks in debug mode
    defer {
        if (builtin.mode == .Debug) {
            std.log.scoped(.program).info("Checking memory leaks from GPA in debug build...", .{});
            _ = gpa.deinit();
        }
    }

    // Initialize the systems
    try renderer.init(allocator);
    defer renderer.deinit();
    try audio.init(allocator);
    defer audio.deinit();
    try ui.init(allocator);
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
                .keydown => |kp| {
                    switch (kp.code) {
                        .c => {
                            sequencer.clear();
                        },
                        .space => {
                            sequencer.togglePlayback();
                        },
                        .r => {
                            try sequencer.randomize();
                        },
                        .left => {
                            sequencer.resetPlayhead();
                        },
                    }
                },
                else => {},
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
            .pos = .{ .x = 8 + 128, .y = 16 },
            .size = .{ .x = 136, .y = 16 },
            .colors = .{ .foreground = .{ .r = @intFromFloat(64 + (attack_time * 255 - 64)), .g = 128, .b = 255 } },
        });
        audio.setAttackTime(attack_time);

        // Draw the speed of the sequencer
        try ui.slider(&sequencer.speed, .{
            .min = 30.0,
            .max = 400.0,
            .pos = .{ .x = 24 + 128 + 128, .y = 16 },
            .colors = .{ .foreground = .{ .r = 255, .g = 128, .b = 64 } },
        });

        // Draw the sequencer
        try sequencer.draw(.{ .x = 16, .y = 48 });

        // Present the frame
        renderer.present();
    }
}

// Logging setup
pub const std_options = struct {
    pub const log_level = if (builtin.mode == .Debug) .debug else .info;
    pub const logFn = coloredLogFn;
};

fn coloredLogLevel(level: std.log.Level) []const u8 {
    // If we're on Windows, don't use ANSI escape codes
    if (builtin.os.tag == .windows) {
        return level.asText();
    }

    // Use ANSI escape codes to color the log level
    // 256 colors for now... might fuck shit up...
    const color = switch (level) {
        .debug => "\x1b[38;5;26m",
        .info => "\x1b[38;5;106m",
        .warn => "\x1b[38;5;214m",
        .err => "\x1b[38;5;160m",
    };

    return color ++ level.asText() ++ "\x1b[0m";
}

pub fn coloredLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = if (scope == .default) ": " else " (" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ comptime coloredLogLevel(level) ++ "]" ++ scope_prefix;

    // Print the message to stderr, silently ignoring any errors
    std.debug.print(prefix ++ format ++ "\n", args);
}
