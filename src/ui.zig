const std = @import("std");

const renderer = @import("renderer.zig");

const Position = struct {
    x: f32,
    y: f32,
};

const Style = struct {
    background: renderer.Color,
    foreground: renderer.Color,
    border: renderer.Color,
    border_width: f32,
    border_radius: f32,
};

const ButtonOptions = struct {
    position: Position,
    size: Position,
    text: []const u8,
};

// fn button(options: ButtonOptions) !bool {

// }
