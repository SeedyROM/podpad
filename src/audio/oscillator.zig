//! A poly BLEP multiple mode oscillator.
//! Based on this (https://www.martin-finke.de/articles/audio-plugins-018-polyblep-oscillator/).
const std = @import("std");

const Self = @This();

/// Each mode for the oscillator.
const Mode = enum {
    sine,
    square,
    saw,
    triangle,
};

frequency: f32 = 440.0,
oscillator_mode: Mode = .sine,
phase_increment: f32 = 0.0,
phase: f32 = 0.0,

pub fn init(
    frequency: f32,
    oscillator_mode: Mode,
) Self {
    return .{
        .phase = 0.0,
        .frequency = frequency,
        .oscillator_mode = oscillator_mode,
    };
}

pub fn next(self: *Self) f32 {
    // Calculate the phase increment
    self.phase_increment = self.frequency * std.math.tau / 44100.0;

    // Make some temporary variables
    var value: f32 = 0.0;
    var t = self.phase / std.math.tau;

    // Calculate the oscillator value based on the mode
    // and add the poly BLEP correction if needed
    switch (self.oscillator_mode) {
        .sine => {
            value = std.math.sin(self.phase);
        },
        .square => {
            if (self.phase < std.math.pi) {
                value = 1.0;
            } else {
                value = -1.0;
            }
            value += self.polyBlep(t);
            value -= self.polyBlep(std.math.mod(f32, t + 0.5, 1.0) catch unreachable);
        },
        .saw => {
            value = (self.phase / std.math.tau) - 1.0;
            value -= self.polyBlep(t);
        },
        .triangle => {
            value = -1.0 + (self.phase / std.math.tau);
            value = (value - std.math.fabs(value) - 0.5);
            value -= self.polyBlep(t);
        },
    }

    // Increment the phase and wrap it around
    self.phase += self.phase_increment;
    if (self.phase >= std.math.tau) {
        self.phase -= std.math.tau;
    }

    return value;
}

/// Calculate the poly BLEP correction for the given phase.
/// Based on this (https://www.martin-finke.de/articles/audio-plugins-018-polyblep-oscillator/).
inline fn polyBlep(self: Self, _t: f32) f32 {
    var dt = self.phase_increment / std.math.tau;
    var t = _t;

    if (t < dt) {
        t /= dt;
        return t + t - t * t - 1.0;
    } else if (t > 1.0 - dt) {
        t = (t - 1.0) / dt;
        return t * t + t + t + 1.0;
    } else {
        return 0.0;
    }
}
