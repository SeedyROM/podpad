//!
//! # The audio system for podpad.
//!
//! This system uses SDL2 to open an audio device and write audio samples to it.
//!
//! It contains:
//! - A simple ADSR envelope generator.
//! - A poly BLEP multiple mode oscillator.
//! - A state variable IIR filter using the bilinear transform.
//! - A simple synth that uses the above components.
//!
const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_audio.h");
});

const util = @import("audio/util.zig");
const Synth = @import("audio/synth.zig");

/// State of the audio system.
const State = struct {
    synth: Synth,

    pub fn init() State {
        return .{
            .synth = Synth.init(440.0),
        };
    }
};

var allocator: std.mem.Allocator = undefined;
var device: c.SDL_AudioDeviceID = 0;
var spec: c.SDL_AudioSpec = undefined;
var _state = State.init();
const audio_log = std.log.scoped(.audio);

pub fn init(_allocator: std.mem.Allocator) !void {
    allocator = _allocator;

    audio_log.debug("Initializing SDL audio subsystem", .{});
    if (c.SDL_Init(c.SDL_INIT_AUDIO) != 0) {
        return error.SDLInitFailed;
    }

    audio_log.debug("Opening audio device", .{});
    spec = c.SDL_AudioSpec{
        .freq = 44100,
        .format = c.AUDIO_F32,
        .channels = 2,
        .silence = 0,
        .samples = 128,
        .padding = 0,
        .size = 0,
        .callback = @ptrCast(&callback),
        .userdata = &_state,
    };
    device = c.SDL_OpenAudioDevice(
        null,
        0,
        &spec,
        null,
        0,
    );

    audio_log.debug("Starting audio device", .{});
    c.SDL_PauseAudioDevice(device, 0);

    audio_log.debug("Initialized audio", .{});
}

pub fn deinit() void {
    audio_log.debug("Pausing audio device", .{});
    c.SDL_PauseAudioDevice(device, 1);
    audio_log.debug("Closing audio device", .{});
    c.SDL_CloseAudioDevice(device);
}

fn callback(userdata: ?*anyopaque, stream: [*c]u8, len: c_int) void {
    // Get the audio system state.
    if (userdata == null) return;
    var state: *State = @ptrCast(@alignCast(userdata));

    // Get an aligned slice of the stream for f32 writing
    const bytes: []align(@alignOf(f32)) u8 = @alignCast(stream[0..@intCast(len)]);
    // Convert the slice to a slice of f32s
    var buffer = std.mem.bytesAsSlice(f32, bytes);

    // Write the audio samples to the stereo buffer

    while (buffer.len > 0) {
        // Apply a -20dB gain to the output
        var x = state.synth.next() * util.dbToLinear(-15);

        // Add some soft clip
        x = util.softClip(x, 1.0);

        buffer[0] = x;
        buffer[1] = x;
        buffer = buffer[2..];
    }
}

pub fn setFrequency(frequency: f32) void {
    _state.synth.oscillator.frequency = frequency;
}

pub fn setFilterFrequency(frequency: f32) void {
    _state.synth.base_frequency = frequency;
}

pub fn setAttackTime(time: f32) void {
    _state.synth.filter_adsr.attack_time = time;
}

pub fn noteOn(note: i32) void {
    _state.synth.noteOn(note);
}

pub fn noteOff() void {
    _state.synth.noteOff();
}

pub fn setADSR(attack: f32, decay: f32, sustain: f32, release: f32) void {
    _state.synth.filter_adsr.attack_time = attack;
    _state.synth.filter_adsr.decay_time = decay;
    _state.synth.filter_adsr.sustain_level = sustain;
    _state.synth.filter_adsr.release_time = release;
}
