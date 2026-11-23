---
title: "Vape LED display with ESPHome"
date: 2026-11-21T22:43:17+11:00
featuredImage: "/blog/vape-led-display-with-esphome/vape_led_display_with_weather.jpeg"

---

Stumbling across a pile of discarded vapes:

> I wonder if I can use them for anything cool...

... was a stupid thought I had one Saturday morning.

<!--more-->

![Pile of vapes](./pile.jpeg)

A brief adventure in getting a disposable vape's LED display working on [ESPHome](https://esphome.io/), allowing me to display the current weather on it. Why? Because it seemed like a fun challenge.

# Exploration

First step was pulling apart the vape. I cut up the plastic bits with a "diamond" cutting bit with my rotary tool, but really any cutting attachment would have worked. I did have to be pretty careful as to not explode the battery in my face, hurt myself with the rotary tool (eye protection!) and to not breathe in plastic dust (ventilation!).

![Cutting open the plastic](./cutting.jpeg)
![Inside the vape](./inside.jpeg)

I realised after that all you really need is something to get some leverage on, then you can use a pair of pliers and just yank the plastic bit at the top really hard to pull out the internals.

Anyway, after that I was left with a battery and a PCB:

![Electronics extracted](./extracted.jpeg)

The battery seems straightforward enough to use, so I had a closer look at the other parts.

![PCB with LED display and airflow pressure switch](./vape_pcb.jpeg)

I was curious about this blue thing, which is apparently a switch for detecting airflow:

![Closeup of airflow pressure switch](./strange_blue_thing.jpeg)

I was guessing that it was also pretty easy to use, just reading the analog signal off of the blue wire, but I'll have a look at it another day.

Then I turned to the LED display. I couldn't tell what was going on, there's no useful markings on this board:

![Underside of PCB with a few useless markings](./underside_of_pcb.jpeg)

None of these mean anything to me, searches show up nothing.

Next step was to try figure out what these 6 pads on the LED display corresponded to: I couldn't tell while it was soldered on, so I took it off:

![Underneath the LED display](./underneath_the_led_display.jpeg)

And we can clearly see that all 6 pads on the LED display have traces directly to the MCU, meaning there's no driver and the MCU drives it directly.

I also found a marking on the LED display itself: `MYFT508`, but I didn't find anything out there on this.

# It works?

ChatGPT recommended starting by connecting each of the pads to a GPIO with a 1k ohm resistor in between each of them (current limiting on GPIOs), and I was feeling lazy so I just soldered them directly to an ESP32C3 I had lying around. I asked it for an external component, set up my YAML and flashed the ESP32C3:

```yaml
vape_led:
  id: my_vape_led
  pads:
    - GPIO0
    - GPIO1
    - GPIO3
    - GPIO6
    - GPIO7
    - GPIO10
```

And it kinda works?

{{< video src="./led_display_flickering.mp4" >}}

Did a fair bit of manual testing of various combinations of GPIOs switched on/off:

![Testing combinations](./testing.png)

This would have been easier with a webcam and an agentic setup but unfortunately I don't have unlimited tokens.

At this point I got stuck: it had this assumption that the LED display was driven by specific waveforms and voltages, but there was some prior research out there I found when I had just about given up:

  * https://gist.github.com/DavidoTek/b12152bffe7ec92f728d80c30b1d798d
  * https://github.com/rleusden/Vape_Display_SY-D66Q-LED
  * https://github.com/32bitnomad/Segment-Display
  * https://github.com/Teiwazik/Fumot-Vape-Display-Library

ChatGPT still got nowhere with this, so I gave Claude a go and it immediately picked up a few things. First was that the LED display uses [charlieplexing](https://en.wikipedia.org/wiki/Charlieplexing) rather than whatever approach ChatGPT was trying.

With a bit of back and forth (human error in my testing and a few final tests needed that clarified the remaining behaviours) we had a full mapping:

![Mappings for the LED display](./mapping.png)

# Tidying it up

Got some helper functions, tied it up into a `display` component so it was conceptually similar to [existing components](https://esphome.io/components/display/pvvx_mithermometer/), made it a bit more pluggable so it can potentially be used with other models and then wired it into my existing Home Assistant sensors:

```yaml
sensor:
  - platform: homeassistant
    id: "weather_temperature"
    entity_id: sensor.sydney_observatory_hill_temp
  - platform: homeassistant
    id: "weather_humidity"
    entity_id: weather.the_suburb_where_i_live
    attribute: humidity

display:
  - platform: vape_led
    id: my_vape_led
    update_interval: 100ms

    # GPIO for pad 1..6, in order.
    pads: [0, 1, 3, 6, 7, 10]

    # Optional: GPIO7 (pad 5) segments were dimmer, so give its row longer.
    pad_slot_us: [1500, 1500, 1500, 1500, 2500, 1500]

    # Segments are [anode, cathode] pad pairs. Pads are numbered from 1.
    # Digits are listed leftmost first.
    digits:
      - { a: [2, 1], b: [3, 1], c: [4, 1], d: [5, 1], e: [6, 1], f: [1, 2], g: [3, 2] }
      - { a: [4, 2], b: [5, 2], c: [6, 2], d: [1, 3], e: [2, 3], f: [4, 3], g: [5, 3] }

    # A symbol is one pair, or a list of pairs. For a list, set_symbol_level()
    # lights them in the order given here.
    symbols:
      percent: [1, 4]
      lightning: [6, 3]
      droplet: [[5, 4], [3, 4], [2, 4]]   # bottom, middle, top
    lambda: !lambda |-
        it.show_value(id(weather_temperature).state);
        auto humidity = id(weather_humidity).state;
        if (std::isfinite(humidity)) {
          if (humidity > 75) {
            it.set_symbol_level("droplet", 3);
          } else if (humidity > 50) {
            it.set_symbol_level("droplet", 2);
          } else {
            it.set_symbol_level("droplet", 1);
          }
        }
```

And there we have it!

![Disposable vape LED display showing the weather from Home Assistant](./vape_led_display_with_weather.jpeg)

Here's some silly animations:

{{< video src="./counter.mp4" >}}
{{< video src="./segment_chase.mp4" >}}

# Conclusion

This might be one of the dumbest things I've made yet. A very satisfying waste of time, would recommend.

You can find the external component here: https://github.com/aarongorka/esphome-components#vape-led-display
