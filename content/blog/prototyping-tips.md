---
title: "Prototyping Tips"
date: 2026-03-11T15:21:05+11:00
# featuredImage: "todo"
draft: true
---

A few tips, learnings and findings on prototyping electronics and "maker" type things.

<!--more-->

Prototyping circuits/devices with e.g. an ESP32 can be bit daunting since there's a myriad of ways to approach it and a lot of products out there. This is a list of things I would have appreciated knowing.

# Pre-crimped JST cables

I've bought a crimper and some parts to crimp my own cables, but I never really got it. I'd rather pay an extra dollar to just get all my cables already crimped (I'm not sure it's even really more expensive).

![photo of JST cable]()

You'll find these on any WS2812B LED strip:

![photo of WS2182B LED strip]()

But you can also just solder any module to them, and you don't have to worry about:

  * Desoldering if you decide to use it elsewhere
  * Having the position tied to a specific location on a board
  * Loose connections with Dupont cables that fall out and leave you debugging why things aren't working

![example of JST cables]()

# XHT60 plugs

If you're using a power supply with a bit of grunt, it's worth decoupling it from your circuit with some of these plugs. Any plug would work, but these are pretty nice to use - the main thing is just being able to unplug it and take your circuit to a bench without dragging your PSU along.

# Bearings

608 bearings are commonly used in 3D printer spool rollers. They're also just handy for anything that needs to roll or spin.

# A good soldering iron

I used to put off a lot of soldering because of how long my cheap soldering iron took to heat up> I got a YIHUA 982 soldering iron station. It's ready to use in a _second_ after turning on, which is awesome for quick fixes.

I'm not recommending this particular model because I've not tried any others so I have no frame of reference for comparisons, but treat yourself to something in this ballpark if you're going to be using your soldering iron more than a few times.

# Lead

Lead is actually the best thing ever. Without it, you're going to be fighting your solder trying to get it to stick to stuff.

I also tried out this super thin kind, which ended up being great.

![photo of lead solder]()

# Flux, flux cleaner, PCB brushes

They're not bad to have, but most of the time I was just trying to compensate for using shit solder. Get good solder and you won't have to worry about these.

# Nuts and bolts

Get yourself one of these M3 kits:

A lot of stuff uses M3, and it's a great size when working with 3D print-sized stuff.

![image of m3 kit]()

And a kit with a range of M3-6 bolts and nuts:

![image of other Mx kit]()

Anything else you can source specifically when you need it.

# Heat inserts?

When I got in to 3D printing, I thought these were _the shit_:

And they are kind of cool, but you'll eventually realise that they're actually functionally the same as just using a nut - but you have to go and heat up a soldering iron to use it. I even built a press for it:

But I wouldn't bother unless you need to screw in to something with limited height/depth where you wouldn't be able to make a recess for a nut.

# Prototype boards? Perfboards/stripboards?

These are... alright. They've probably helped me out a few times, but they've also just gotten in the way a lot of the time. I've actually stopped using them as much as I can, particular the prototype boards, because it's so difficult to precisely join 2 connections to one point.

![shitty prototype board soldering]()

Perfboards/stripboards kind of fix this problem, but they're not as common.

![slightly less shitty perfboard]()

I've also experimented with doing 3D printed "plates" to organise modules:

![3d printed plate with modules stuck on]()

Which can be a bit easier, although they don't like heat.

I think the real solution here is to just prototype with whatever and then get a design in to KiCad.

# Blu Tack (or equivalent)

This stuff is _great_ for making your prototypes hold together just long enough to prove they work.

Loose cables?

![photo of loose cables held together by Blu Tack]()

Didn't measure your mounting holes right?

![photo of module mounted to print by Blu Tack]()
