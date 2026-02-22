Server.supernova;
s.waitForBoot {
Ndef(\ambient2, {
    var freqs = Array.series(8, 100, 100);
    var trig = Impulse.kr(1) + Impulse.kr(3/8);
    var blip = SinOsc.ar(Demand.kr(trig, 0, Drand(freqs, inf)), mul: 0.6) * Env.perc(0, 0.4).kr(gate: trig);
    var bass = Pan2.ar(LPF.ar(
        Saw.ar(50 * {LFNoise1.kr(1).bipolar(1/4).midiratio}!8, mul: LFTri.kr(2).range(0.2, 0.5)),
        SinOsc.kr(1/4).range(300, 1000),
    ).sum * 0.4, 0);
    var sig = 0;
    freqs.do{ |freq|
        var detune = {LFNoise1.kr(1/4).bipolar(1/2).midiratio}!8;
        var voice = PMOsc.ar(
            freq * detune,
            LFNoise1.kr(1/7).exprange(4, 400),
            LFNoise1.kr(1/9).range(0, 3)
        ) * 0.1;
        voice = LPF.ar(voice, LFNoise0.kr(LFNoise0.kr(1/4).range(1, 8)).exprange(300, 9000));
        sig = sig + Pan2.ar(voice.sum, SinOsc.kr(1/3), 0.2);
    };
    sig = sig + bass;
    sig = sig + Pan2.ar(CombL.ar(blip, 1, 1/2, 3), LFNoise1.kr(1));
    sig = XFade2.ar(sig, NHHall.ar(sig));
}).play(fadeTime: 5);
}
