//! The synth for this project

const std = @import("std");

const util = @import("util.zig");
const ADSR = @import("adsr.zig");
const DCBlocker = @import("dc_blocker.zig");
const IIRFilter = @import("iir_filter.zig");
const Oscillator = @import("oscillator.zig");
const Distortion = @import("distortion.zig");

const Self = @This();
const synth_log = std.log.scoped(.synth);

amp_adsr: ADSR,
base_frequency: f32 = 5000.0,
dc_blocker: DCBlocker = DCBlocker.init(),
filter_adsr: ADSR,
filter: IIRFilter,
gain: f32,
oscillator: Oscillator,
distortion: Distortion,

last_value: f32 = 0.0,

pub fn init(
    frequency: f32,
) Self {
    var amp_adsr = ADSR.init(44100.0);
    amp_adsr.attack_time = 0.01;
    amp_adsr.decay_time = 1.0;
    amp_adsr.sustain_level = 1.0;
    amp_adsr.release_time = 0.3;

    var filter_adsr = ADSR.init(44100.0);
    filter_adsr.attack_time = 0.01;
    filter_adsr.decay_time = 0.1;
    filter_adsr.sustain_level = 0.1;
    filter_adsr.release_time = 0.3;

    return .{
        .oscillator = Oscillator.init(frequency, .sine),
        .filter_adsr = filter_adsr,
        .amp_adsr = amp_adsr,
        .filter = IIRFilter.init(.lowpass, 1000.0, 2.5, 1.0),
        .gain = 1.0,
        .distortion = .{},
    };
}

pub fn noteOn(self: *Self, note: i32) void {
    self.oscillator.frequency = util.midiNoteToPitch(note);
    self.filter_adsr.noteOn();
    self.amp_adsr.noteOn();

    synth_log.debug("Note on: {} ({d})", .{ note, self.oscillator.frequency });
}

pub fn noteOff(self: *Self) void {
    self.amp_adsr.noteOff();
    self.filter_adsr.noteOff();
}

pub fn next(self: *Self) f32 {
    // Calculate the filter cutoff based on the filter ADSR envelope
    const cutoff = 10 + (self.base_frequency * self.filter_adsr.next());
    self.filter.setFrequency(cutoff);

    // Next oscillator sample, apply DC blocker
    var osc_sample = self.dc_blocker.next(self.oscillator.next());

    // Filter the signal of the oscillator, then apply the ADSR envelope and gain
    var x = self.filter.next(osc_sample) * self.amp_adsr.next() * self.gain;

    // Apply distortion
    x = self.distortion.next(x);

    self.last_value = x;

    return x;
}
