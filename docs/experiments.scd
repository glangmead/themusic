Server.supernova;
s.waitForBoot{
(
~root = -13;
~revSend = Bus.audio(s, 2);
);
(
		SynthDef(\bell, {
			|
			freq=556, findex=0, frate=2,
			dur=5, pos=0,
			amp=0.25,
			out=0
			|
			var sigA, sigB, sigC, sig, env, fmod;
			// handy not to care about noteOn/noteOff. doneAction:2 means "free the synth when the envelope is done"
			env = EnvGen.ar(Env.triangle(5), doneAction:2);
			// vibrato right? but sin + 0.5
			fmod = findex * SinOsc.kr(frate, mul:0.5, add:0.5) * Line.kr(0, 1, 7);
			// square, random walk of widths
			sigA = Pulse.ar(freq + fmod, LFNoise2.kr(1).range(0.2, 0.8) );
			sigB = VarSaw.ar(freq + fmod);
			sigC = WhiteNoise.ar() * 0.125;
			sig = SelectX.ar(LFNoise2.kr(2).range(0, 2), [sigA, sigB, sigC]); // two at a time are playing, not 3. I can use osc1mix, osc2mix, osc3mix

			sig = LPF.ar(sig, freq*4 ); // express cutoff in terms of freq, hmm
			sig = sig * env * amp;
			Out.ar(out, Pan2.ar(sig, pos));
		}).add;

		s.sync;

		SynthDef(\rev, {
			arg in=0, out=0, mix=1, room=0.8;
			var sig;
			sig = In.ar(in, 2);
			sig = FreeVerb.ar(sig, mix, room);
			Out.ar(out, sig);
		}).add;

		s.sync;

		~rev = Synth(\rev, [\in, ~revSend]); // DC.ar(400)

		x = Pbind(
			\instrument, \bell,
			\out, ~revSend,
			\root, Pfunc({~root}),
			\octave, Pwrand([4, 5, 6, 7], [6,8,3,1].normalizeSum, inf),
			\degree, Prand(Scale.lydian.degrees, inf),
			\ctranspose, Pwhite( -0.05, 0.05, inf),
			\amp, 1.1 * Pexprand(0.001, 0.7) * (1/(Pkey(\octave)+1)),
			\findex, Pexprand(2, 20),
			\frate, Pwhite(1, 25, inf),
			\pos, Pwhite(-0.8, 0.8, inf), // position in space
			\dur, Pwhite(0.1, 0.5), // this blocks off an interval of time from other generators. We tile R with Z blocks.
		).asEventStreamPlayer;
		x.trace.play;

		wait(15);
		r = Routine({
			"starting".postln;
			loop({
				~root = [-13, -1, 4, 7].choose;
				wait( 10.rrand(25) );
			});
		});
		r.play;
)}



(
{
    var a;
    a = [
            SinOsc.ar,
            Saw.ar(300),
            LFNoise2.ar(2000)
        ];

    SelectX.ar(MouseX.kr(0, 3), a)
}.play;
)

x.trace;
(note + gtranspose + root)/stepsPerOctave * octave * 12

(
{
    var a;
    a = [
            LFNoise0.ar(2000),
            LFNoise1.ar(2000),
            LFNoise2.ar(2000)
        ];

    SelectX.ar(MouseX.kr(0, 3), a)
}.play;
)

{LFNoise0.ar(5000)}.plot
{LFNoise1.ar(5000)}.plot
{LFNoise0.ar(Line.ar(1000, 5000, 10))}.play // 5000 random numbers per second, but
{LPF.ar(LFNoise0.ar(5000), 1800 )}.play
{LFNoise2.ar(2000)}.play

{SinOsc.ar(800, mul: LFNoise2.kr(7))}.scope

{Dust.ar(5000)}.plot;


(
 {var trig = Dust.kr(10);
  SinOsc.ar(TRand.kr(300, 3000, trig)) * 0.1
 }.play;
)

{Pulse.ar(440, LFNoise2.kr(1).range(0.1, 0.95) )}.play

{
var fmod = SinOsc.kr(2, mul:0.5, add:0.5) * Line.kr(0, 1, 7);
var freq = 330;
var sigA = Pulse.ar(freq+fmod, LFNoise2.kr(1).range(0.2, 0.8) );
var sigB = VarSaw.ar(freq+fmod);
var sigC = WhiteNoise.ar() * 0.125;
var sig = SelectX.ar(LFNoise2.kr(2).range(0, 2), [sigA, sigB, sigC]);
	sig = LPF.ar(sig, (freq)*4 );
	sig = FreeVerb.ar(sig, 1, 0.8);
}.play




// vibrato at 1 Hz, note the use of DC.ar UGen; a constant of 400.0 doesn't work
{ SinOsc.ar(Vibrato.ar(DC.ar(400.0), 1, 0.02)) }.play

// compare: k-rate freq input can be a constant
{ SinOsc.ar(Vibrato.kr(400.0, 1, 0.02)) }.play

// control rate and rateVariation
{ SinOsc.ar(Vibrato.ar(DC.ar(400.0), MouseX.kr(2.0, 100.0), 0.1, 1.0, 1.0, MouseY.kr(0.0, 1.0), 0.1)) }.play

// control depth and depthVariation
{ SinOsc.ar(Vibrato.ar(DC.ar(400.0), LFNoise1.kr(1, 3, 7), MouseX.kr(0.0, 1.0), 1.0, 1.0, MouseY.kr(0.0, 1.0), 0.1)) }.play