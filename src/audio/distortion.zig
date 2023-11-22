const std = @import("std");
const util = @import("util.zig");
const Self = @This();

const ClipType = enum {
    /// Soft clipping using the hyperbolic tangent function.
    tanh,
    /// Soft clipping using an exponential function.
    exponential,
    /// Hard clipping using a diode function.
    diode,
};

gain: f32 = 1.0,
threshold: f32 = 1.0,
clip_type: ClipType = .diode,

const one_third: f32 = 1.0 / 3.0;
const two_thirds: f32 = 2.0 / 3.0;

pub fn next(self: *const Self, value: f32) f32 {
    // Scale the input value by the gain and add the bias.
    var x = value * self.gain;

    // Clip the value.
    switch (self.clip_type) {
        .tanh => {
            // Just use the hyperbolic tangent function, simple and fast.
            x = std.math.tanh(x);
        },
        // TODO(SeedyROM): This is broken as fuck.
        .diode => {
            x = diodeClip(x, self.threshold) * self.gain;
        },
        .exponential => {
            // Exponential step function.
            if (x > 0.0) {
                x = -1 + @exp(x);
            } else if (x < 0.0) {
                x = 1 + @exp(-x);
            } else {
                x = 0.0;
            }
        },
    }

    // Compensate for the gain
    return x / self.gain;
}

fn diodeClip(input: f32, threshold: f32) f32 {
    var in_val: f32 = @fabs(input) / threshold;
    var out_val: f32 = 0.0;

    if (in_val <= 1.0 / 3.0) {
        out_val = 2.0 * in_val;
    } else if (in_val <= 2.0 / 3.0) {
        out_val = -3.0 * std.math.pow(f32, in_val, 2) + 4.0 * in_val - 1.0 / 3.0;
    } else {
        out_val = 1.0;
    }

    // Undo normalization and recover sign
    out_val *= threshold;
    if (input <= 0) out_val = -out_val;

    return out_val;
}
