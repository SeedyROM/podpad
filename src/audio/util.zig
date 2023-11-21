//! Audio utilities.

const std = @import("std");

/// Converts a MIDI note number to a frequency in Hz.
pub fn midiNoteToPitch(note: i32) f32 {
    return 440.0 * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(note - 69)) / 12.0);
}

/// Soft clip the given input with the given threshold.
pub fn softClip(input: f32, threshold: f32) f32 {
    if (input > threshold) {
        return threshold + (1 - std.math.exp(-input + threshold));
    } else if (input < -threshold) {
        return -threshold - (1 - std.math.exp(input + threshold));
    } else {
        return input;
    }
}

/// Calculate a linear value from dB.
pub inline fn dbToLinear(db: f32) f32 {
    return std.math.pow(f32, 10.0, db / 20.0);
}
