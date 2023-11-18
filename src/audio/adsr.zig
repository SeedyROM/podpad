//! A simple ADSR envelope generator.
const Self = @This();

attack_time: f32,
decay_time: f32,
sustain_level: f32,
release_time: f32,
sample_rate: f32,

state: State,
envelope_value: f32,
time_since_note_on: f32,
time_since_note_off: f32,

const State = enum { attack, decay, sustain, release, off };

pub fn init(sample_rate: f32) Self {
    return .{
        .attack_time = 0.01,
        .decay_time = 0.1,
        .sustain_level = 0.1,
        .release_time = 0.3,
        .sample_rate = sample_rate,
        .state = .off,
        .envelope_value = 0.0,
        .time_since_note_on = 0.0,
        .time_since_note_off = 0.0,
    };
}

pub fn noteOn(self: *Self) void {
    self.state = .attack;
    self.time_since_note_on = 0.0;
}

pub fn noteOff(self: *Self) void {
    self.state = .release;
    self.time_since_note_off = 0.0;
}

/// Calculate the next envelope value.
pub fn next(self: *Self) f32 {
    const sample_increment = 1.0 / self.sample_rate;

    switch (self.state) {
        .attack => {
            self.envelope_value += sample_increment / self.attack_time;
            self.time_since_note_on += sample_increment;

            if (self.envelope_value >= 1.0 or self.time_since_note_on >= self.attack_time) {
                self.envelope_value = 1.0;
                self.state = .decay;
            }
        },
        .decay => {
            self.envelope_value -= sample_increment / self.decay_time * (1.0 - self.sustain_level);
            self.time_since_note_on += sample_increment;

            if (self.envelope_value <= self.sustain_level or self.time_since_note_on >= (self.attack_time + self.decay_time)) {
                self.envelope_value = self.sustain_level;
                self.state = .sustain;
            }
        },
        .sustain => {
            // In sustain state, the envelope value stays constant
            self.envelope_value = self.sustain_level;
        },
        .release => {
            self.envelope_value -= sample_increment / self.release_time * self.sustain_level;
            self.time_since_note_off += sample_increment;

            if (self.envelope_value <= 0.0 or self.time_since_note_off >= self.release_time) {
                self.envelope_value = 0.0;
                self.state = .off;
            }
        },
        .off => {},
    }

    return self.envelope_value;
}
