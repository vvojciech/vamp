setcps(112/60/4);
(
arrange(
[16, stack(
  (
arrange(
  [8, (
s("bd*4, [~ cp]*2, [~ hh]*4").gain(0.9)
  )],
  [8, (
s("bd*4, [~ cp]*2, [~ hh]*4").gain(0.9)
  )]
)
  ).postgain(0.85),
  (
arrange(
  [8, (
note("<c2 c2 ab1 bb1>*8")
  .s("sawtooth").lpf(sine.range(300, 1400).slow(8)).lpq(6)
  .decay(0.18).sustain(0)
  )],
  [8, (
note("<c2 c2 ab1 bb1>*8")
  .s("sawtooth").lpf(sine.range(300, 1400).slow(8)).lpq(6)
  .decay(0.18).sustain(0)
  )]
)
  ).postgain(0.70),
  (
arrange(
  [8, silence],
  [8, (
chord("<Cm9 Ab^7 Fm9 Bb7>").voicing()
  .s("supersaw").lpf(1600).attack(0.08).release(0.8)
  .room(0.5).gain(0.3)
  )]
)
  ).postgain(0.60),
  (
arrange(
  [8, silence],
  [8, (
n("0 2 4 [7 9] 4 2 [0 -3] ~").scale("<C4:minor Ab3:major F3:minor Bb3:mixolydian>")
  .s("triangle").decay(0.2).sustain(0)
  .delay(0.35).delaytime(0.1875).room(0.3)
  )]
)
  ).postgain(0.50)
)],
[2, silence]
)
).early(8)