//!
//! # Sequencer
//!
//! The sequencer is a 16x16 grid of pads. Each pad represents a note in the C Major scale.
//!
const std = @import("std");

const ui = @import("../ui.zig");
const audio = @import("../audio.zig");
const renderer = @import("../renderer.zig");

const Vec2i = renderer.Vec2i;
const Rect = renderer.Rect;
const Color = renderer.Color;

const Pad = struct {
    on: bool = false,
    note: i32 = 0,
    hovered: bool = false,
    position: Vec2i = .{ .x = 0, .y = 0 },
    active: bool = false,

    const size = 16;

    pub fn init(note: i32) Pad {
        return .{
            .on = false,
            .note = note,
            .hovered = false,
            .position = .{ .x = 0, .y = 0 },
            .active = false,
        };
    }

    pub fn draw(self: *Pad, pos: Vec2i) !void {
        var position = pos;

        if (self.active and self.on) {
            position.y -= 2;
        }

        if (try ui.button(
            .{
                .pos = position,
                .size = .{ .x = Pad.size, .y = Pad.size },
                .colors = .{
                    .background = .{ .r = 64, .g = 64, .b = 64 },
                    .hovered = .{ .r = 128, .g = 128, .b = 128 },
                    .active = .{ .r = 255, .g = 255, .b = 255 },
                },
                .active = &self.on,
                .hovered = &self.active,
            },
        )) {
            self.on = !self.on;
        }
    }
};

const Column = struct {
    pads: []Pad,

    pub fn init() !Column {
        var column = .{
            .pads = try ui.allocator.alloc(Pad, 16),
        };

        // Initialize each pad
        for (0..column.pads.len) |i| {
            var pad = Pad.init(@intCast(45 + 16 - i));
            column.pads[i] = pad;
        }

        return column;
    }

    pub fn deinit(
        self: *Column,
    ) void {
        ui.allocator.free(self.pads);
    }

    pub fn draw(self: *Column, pos: Vec2i) !void {
        // Draw each pad in the column vertically spaced out by 24 pixels
        for (0..self.pads.len) |_i| {
            var pad = &self.pads[_i];
            const i = @as(i32, @intCast(_i));
            try pad.draw(.{ .x = pos.x, .y = pos.y + (i * 24) });
        }
    }
};

const Pattern = struct {
    columns: []Column,

    /// Initialize an empty pattern
    pub fn init() !Pattern {
        var _pattern = .{
            .columns = try ui.allocator.alloc(Column, 16),
        };

        // Initialize each column
        for (0.._pattern.columns.len) |i| {
            var column = try Column.init();
            _pattern.columns[i] = column;
        }

        return _pattern;
    }

    /// Initialize a random pattern
    pub fn initRandom() !Pattern {
        var _pattern = .{
            .columns = try ui.allocator.alloc(Column, 16),
        };

        // Create a prng
        var prng = std.rand.DefaultPrng.init(@intCast(std.time.microTimestamp()));

        // Initialize every 4th column
        for (0.._pattern.columns.len) |i| {

            // Initialize the column
            var column = try Column.init();
            _pattern.columns[i] = column;

            // Generate a random pad index
            const randomPadIndex = prng.random().int(u32) % 16;
            // Set a random pad for the column
            if (i % 4 != 0) {
                column.pads[randomPadIndex].on = true;
            }
        }

        return _pattern;
    }

    pub fn deinit(
        self: *Pattern,
    ) void {
        for (0..self.columns.len) |i| {
            var column = self.columns[i];
            column.deinit();
        }
        ui.allocator.free(self.columns);
    }

    pub fn draw(self: *Pattern, pos: Vec2i) !void {
        // Draw each column in the pattern spaced out by 24 pixels
        for (0..self.columns.len) |_i| {
            var column = &self.columns[_i];
            const i = @as(i32, @intCast(_i));
            try column.draw(.{ .x = pos.x + (i * 24), .y = pos.y });
        }
    }
};

var pattern: Pattern = undefined;
var duration: f32 = 0.0;
var currentColumn: usize = 0;

pub fn init() !void {
    pattern = try Pattern.initRandom();
}

pub fn deinit() void {
    pattern.deinit();
}

pub fn update() void {
    // Update the current column and play the notes
    duration += ui.frame_time;

    if (duration >= 300.0) {
        duration = 0.0;
        currentColumn += 1;
        if (currentColumn >= pattern.columns.len) {
            currentColumn = 0;
        }

        // Clear the previous column of active pads
        var last_column_index: usize = 0;
        if (currentColumn == 0) {
            last_column_index = pattern.columns.len - 1;
        } else {
            last_column_index = currentColumn - 1;
        }
        var last_column = &pattern.columns[last_column_index];
        for (0..last_column.pads.len) |i| {
            var pad = &last_column.pads[i];
            if (pad.on) {
                audio.noteOff();
            }
            pad.active = false;
        }

        // Set the current column's pads to active and play the notes
        var column = &pattern.columns[currentColumn];
        for (0..column.pads.len) |i| {
            var pad = &column.pads[i];
            pad.active = true;
            if (pad.on) {
                audio.noteOn(pad.note);
            }
        }
    }
}

pub fn draw(pos: Vec2i) !void {
    try pattern.draw(pos);
}
