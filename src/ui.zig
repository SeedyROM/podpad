//!
//! # UI is a simple immediate mode UI library
//!
//! - [x] Add a slider
//! - [x] Add a button
//!
const std = @import("std");

const audio = @import("audio.zig");
const renderer = @import("renderer.zig");

const Vec2i = renderer.Vec2i;
const Rect = renderer.Rect;
const Color = renderer.Color;

pub var allocator: std.mem.Allocator = undefined;

pub var mouse_position: Vec2i = .{ .x = 0, .y = 0 };
pub var is_mouse_down: bool = false;
pub var is_mouse_clicked: bool = false;
pub var frame_time: f32 = 0.0;

pub fn init(_allocator: std.mem.Allocator) !void {
    allocator = _allocator;
}

pub fn deinit() void {}

pub fn update(mouse_pos: Vec2i, is_down: bool, is_clicked: bool, dt: f32) void {
    mouse_position = mouse_pos;
    is_mouse_down = is_down;
    is_mouse_clicked = is_clicked;
    frame_time = dt;
}

pub const button_opts = struct {
    active: bool = false,
    hovered: bool = false,
    pos: Vec2i = .{ .x = 0, .y = 0 },
    size: Vec2i = .{ .x = 16, .y = 16 },
    colors: struct {
        background: Color = .{ .r = 64, .g = 64, .b = 64 },
        hovered: Color = .{ .r = 128, .g = 128, .b = 128 },
        active: Color = .{ .r = 255, .g = 255, .b = 255 },
    } = .{},
};

pub fn button(opts: button_opts) !bool {
    // If the mouse is over the button
    const is_mouse_over = mouse_position.x >= opts.pos.x and
        mouse_position.x <= opts.pos.x + opts.size.x and
        mouse_position.y >= opts.pos.y and
        mouse_position.y <= opts.pos.y + opts.size.y;

    // Draw the button
    if (is_mouse_over) {
        if (is_mouse_clicked) {
            try renderer.drawRect(
                .{
                    .x = opts.pos.x,
                    .y = opts.pos.y,
                    .w = opts.size.x,
                    .h = opts.size.y,
                },
                opts.colors.active,
            );
            return true;
        }

        try renderer.drawRect(
            .{
                .x = opts.pos.x,
                .y = opts.pos.y,
                .w = opts.size.x,
                .h = opts.size.y,
            },
            opts.colors.hovered,
        );
    } else {
        try renderer.drawRect(
            .{
                .x = opts.pos.x,
                .y = opts.pos.y,
                .w = opts.size.x,
                .h = opts.size.y,
            },
            opts.colors.background,
        );
    }

    // If hovered is true, draw the button as hovered
    if (opts.hovered) {
        try renderer.drawRect(
            .{
                .x = opts.pos.x,
                .y = opts.pos.y,
                .w = opts.size.x,
                .h = opts.size.y,
            },
            opts.colors.hovered,
        );
    }

    // If active is true, draw the button as active
    if (opts.active) {
        try renderer.drawRect(
            .{
                .x = opts.pos.x,
                .y = opts.pos.y,
                .w = opts.size.x,
                .h = opts.size.y,
            },
            opts.colors.active,
        );
    }

    return false;
}

pub const slider_opts = struct {
    direction: enum(u1) {
        horizontal,
        vertical,
    } = .horizontal,
    pos: Vec2i = .{ .x = 0, .y = 0 },
    size: Vec2i = .{ .x = 112, .y = 16 },
    min: f32 = 0.0,
    max: f32 = 1.0,
    step: f32 = 0.0,
    colors: struct {
        background: Color = .{ .r = 64, .g = 64, .b = 64 },
        foreground: Color = .{ .r = 255, .g = 255, .b = 255 },
    } = .{},
};

pub fn slider(value: *f32, opts: slider_opts) !void {
    // Normalize the value
    var normalized_value = (value.* - opts.min) / (opts.max - opts.min);

    //
    // Update state
    //

    // If the mouse is over the slider
    const is_mouse_over = mouse_position.x >= opts.pos.x and
        mouse_position.x <= opts.pos.x + opts.size.x and
        mouse_position.y >= opts.pos.y and
        mouse_position.y <= opts.pos.y + opts.size.y;

    // If the mouse is over the slider and the mouse is down
    if (is_mouse_over and is_mouse_down) {
        // Calculate the normalized value of the slider
        var normalized_mouse_position_x: f32 = 0.0;
        var normalized_mouse_position_y: f32 = 0.0;
        if (opts.direction == .horizontal) {
            normalized_mouse_position_x = @as(f32, @floatFromInt(mouse_position.x - opts.pos.x)) / @as(f32, @floatFromInt(opts.size.x));
        } else {
            // Get normalized position of the mouse upside down
            normalized_mouse_position_y = 1.0 - (@as(f32, @floatFromInt(mouse_position.y - opts.pos.y)) / @as(f32, @floatFromInt(opts.size.y)));
        }

        // Calculate the new value of the slider
        var new_value = opts.min + (normalized_mouse_position_x * (opts.max - opts.min));
        if (opts.direction == .vertical) {
            new_value = opts.min + (normalized_mouse_position_y * (opts.max - opts.min));
        }

        // Round the new value to the nearest step if a step is specified
        var rounded_new_value = new_value;
        // TODO(SeedyROM): This doesn't work.
        // if (opts.step > 0.0) {
        //     rounded_new_value = new_value - (std.math.mod(f32, new_value, opts.step) catch unreachable);
        // }

        // Set the value
        value.* = rounded_new_value;
    }

    //
    // Draw the slider
    //

    // Draw the background
    try renderer.drawRect(
        .{
            .x = opts.pos.x,
            .y = opts.pos.y,
            .w = opts.size.x,
            .h = opts.size.y,
        },
        opts.colors.background,
    );

    // Draw the foreground
    var normalized_size = normalized_value * @as(f32, @floatFromInt(opts.size.x));
    if (opts.direction == .vertical) {
        normalized_size = normalized_value * @as(f32, @floatFromInt(opts.size.y));
    }
    var current_value_size = @as(i32, @intFromFloat(normalized_size));

    if (opts.direction == .horizontal) {
        try renderer.drawRect(
            .{
                .x = opts.pos.x,
                .y = opts.pos.y,
                .w = current_value_size,
                .h = opts.size.y,
            },
            opts.colors.foreground,
        );
    } else {
        // Draw the foreground upside down
        try renderer.drawRect(
            .{
                .x = opts.pos.x,
                .y = opts.pos.y + opts.size.y - current_value_size,
                .w = opts.size.x,
                .h = current_value_size,
            },
            opts.colors.foreground,
        );
    }
}

const adsr_opts = struct {
    pos: Vec2i = .{
        .x = 0,
        .y = 0,
    },
};

pub fn adsr(attack: *f32, decay: *f32, sustain: *f32, release: *f32, opts: adsr_opts) !void {
    try slider(attack, .{
        .direction = .vertical,
        .pos = opts.pos,
        .size = .{ .x = 16, .y = 112 },
        .min = 0.0,
        .max = 1.0,
        .step = 0.0,
        .colors = .{
            .background = .{ .r = 64, .g = 64, .b = 64 },
            .foreground = .{ .r = 255, .g = 255, .b = 255 },
        },
    });

    try renderer.drawText(
        "default",
        "A",
        .{ .x = opts.pos.x + 4, .y = opts.pos.y + 112 - 8 },
        .{ .r = 255, .g = 255, .b = 255 },
    );

    try slider(decay, .{
        .direction = .vertical,
        .pos = .{ .x = 8 + opts.pos.x + 16, .y = opts.pos.y },
        .size = .{ .x = 16, .y = 112 },
        .min = 0.0,
        .max = 1.0,
        .step = 0.0,
        .colors = .{
            .background = .{ .r = 64, .g = 64, .b = 64 },
            .foreground = .{ .r = 255, .g = 255, .b = 255 },
        },
    });

    try renderer.drawText(
        "default",
        "A",
        .{ .x = 8 + opts.pos.x + 16 + 4, .y = opts.pos.y + 112 - 8 },
        .{ .r = 255, .g = 255, .b = 255 },
    );

    try slider(sustain, .{
        .direction = .vertical,
        .pos = .{ .x = 16 + opts.pos.x + 32, .y = opts.pos.y },
        .size = .{ .x = 16, .y = 112 },
        .min = 0.0,
        .max = 1.0,
        .step = 0.0,
        .colors = .{
            .background = .{ .r = 64, .g = 64, .b = 64 },
            .foreground = .{ .r = 255, .g = 255, .b = 255 },
        },
    });

    try renderer.drawText(
        "default",
        "S",
        .{ .x = 16 + opts.pos.x + 32 + 4, .y = opts.pos.y + 112 - 8 },

        .{ .r = 255, .g = 255, .b = 255 },
    );

    try slider(release, .{
        .direction = .vertical,
        .pos = .{ .x = 8 + opts.pos.x + 64, .y = opts.pos.y },
        .size = .{ .x = 16, .y = 112 },
        .min = 0.0,
        .max = 3.0,
        .step = 0.0,
        .colors = .{
            .background = .{ .r = 64, .g = 64, .b = 64 },
            .foreground = .{ .r = 255, .g = 255, .b = 255 },
        },
    });

    try renderer.drawText(
        "default",
        "R",
        .{ .x = 12 + opts.pos.x + 64, .y = opts.pos.y + 112 - 8 },
        .{ .r = 255, .g = 255, .b = 255 },
    );
}
