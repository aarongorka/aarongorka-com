---
title: "GoPro Video Fixing Adventure"
date: 2023-09-19T13:30:28+10:00
featuredImage: "/gopro_quik.png"
---

A summary of my adventures in the GoPro Quik app, mp4 metadata, root on Android, ADB, static linking and `ffmpeg` in Termux.

<!--more-->

{{< load-photoswipe >}}
{{< figure src="/gopro_quik.png" >}}

I recently discovered the GoPro Quik app for editing my videos, and while I had a lot of success with it, it had one fatal flaw: **certain specific videos could not be edited**. I could import them, load them in to the app, include them in a clip, but I could not (manually) trim them - meaning I'd have to rely on the "auto-highlight" feature which missed a lot of moments I really wanted to include. Every time I tried, I'd get the error above:

> An error occurred

> We need to revert your edit.

Maybe someone out there will get the same error some day, or maybe you'll just enjoy the rabbithole I went down to fix this.

  * Compared working videos with `mediainfo` and `ffprobe`. Some strange differences like lengths being inconsistent in the broken videos, but nothing clear
  * Discovered that the built-in "trim" functionality in the android gallery app fixes the videos
  * Realised the dates were wrong - time was reset on GoPro, so all videos were from 2016
  * Came across a suggestion to fix videos by doing a passthrough with `ffmpeg`: `ffmpeg -i in.mp4 -c copy out.mp4`
  * Don't want to transfer all videos back and forth between laptop and phone
  * Can't fix from laptop over MTP mount, the files (videos) are hidden by app
  * Can use root to access hidden files?
  * Ghost Commander isn't working with root?
  * "File" does work!
  * Path is different to what's documented on the internet. It's actually: `/data/data/com.gopro.smarty/no_backup/softtubes/<numbers?>/100GOPRO`
  * Filenames are slightly different to exports e.g. `GH011880_ALTA827199470536694760.MP4` vs `GH011880_ALTA-827199470536694760.MP4`
  * `adb shell` from laptop
  * `su` - but I don't have `ffmpeg` installed on my phone yet
  * How can I run [`termux`](https://github.com/termux/termux-app/) as root via ADB?
  * https://github.com/termux/termux-app/issues/77#issuecomment-260223391
    ```
    export PREFIX='/data/data/com.termux/files/usr'
    export HOME='/data/data/com.termux/files/home'
    export LD_LIBRARY_PATH='/data/data/com.termux/files/usr/lib'
    export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:$PATH"
    export LANG='en_US.UTF-8'
    export SHELL='/data/data/com.termux/files/usr/bin/bash'
    cd "$HOME"
    exec "$SHELL" -l
    ```
    and
    ```
    su $(stat -c %u /data/data/com.termux) /data/data/com.termux/files/home/bin/termux-shell.sh
    ```
  * Seems there's some Android funny business going on here where you need to be in the "context" (SELinux context?) of the right app to edit files belonging to it
  * Can't run `pkg` as root... Installed `ffmpeg` directly on the phone
  * Tried to run `ffmpeg`: missing `libexpat1.so.1` library...
  * `pkg upgrade` from phone
  * `CANNOT LINK EXECUTABLE "../usr/bin/ffmpeg": cannot locate symbol "Xzs_Construct" referenced by "/system/lib64/libunwindstack.so"...`
  * Playing with `$LD_LIBRARY_PATH`:
    ```
    ~ $ export LD_LIBRARY_PATH='/data/data/com.termux/files/usr/lib:/system/lib'                                                                                                                           
    ~ $ ffmpeg                                                                                                                                                                                             
    CANNOT LINK EXECUTABLE "ffmpeg": library "libm.so" needed or dlopened by "/data/data/com.termux/files/usr/bin/ffmpeg" is not accessible for the namespace "(default)"                                  
    ~ $ ls /system/lib/libm.so                                                                                                                                                                             
    CANNOT LINK EXECUTABLE "ls": library "libc.so" needed or dlopened by "/data/data/com.termux/files/usr/bin/coreutils" is not accessible for the namespace "(default)"
    ```
  * So there's this real funny situation with Termux binaries in that they're linked to the Android libraries, but also Termux ones. But I can't figure out the right combination to get Termux binaries to run.
  * `../usr/bin/tsu "$(stat -c %u /data/data/com.termux)"` maybe this will work?
  * What if I do `export LD_LIBRARY_PATH='/system/lib64:/data/data/com.termux/files/usr/lib'`? It works:
    ```
    :/data/data/com.termux/files/home $ sudo ffprobe -hide_banner /data/data/com.gopro.smarty/no_backup/imports/PXL_20230825_042933152_1693971297528.MP4
    Input #0, mov,mp4,m4a,3gp,3g2,mj2, from '/data/data/com.gopro.smarty/no_backup/imports/PXL_20230825_042933152_1693971297528.MP4':
      Metadata:
        major_brand     : mp42
        minor_version   : 0
        compatible_brands: isommp42
        creation_time   : 2023-08-25T04:29:42.000000Z
        com.android.capture.fps: 30.000000
      Duration: 00:00:08.90, start: 0.000000, bitrate: 13501 kb/s
      Stream #0:0[0x1](eng): Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 191 kb/s (default)
        Metadata:
          creation_time   : 2023-08-25T04:29:42.000000Z
          handler_name    : SoundHandle
          vendor_id       : [0][0][0][0]
      Stream #0:1[0x2](eng): Video: h264 (High) (avc1 / 0x31637661), yuvj420p(pc, bt470bg/bt470bg/smpte170m, progressive), 1920x1080, 13305 kb/s, SAR 1:1 DAR 16:9, 30.11 fps, 30 tbr, 90k tbn (default)
        Metadata:
          creation_time   : 2023-08-25T04:29:42.000000Z
          handler_name    : VideoHandle
          vendor_id       : [0][0][0][0]
        Side data:
          displaymatrix: rotation of -90.00 degrees
    :/data/data/com.termux/files/home $ 
    ```
  * Did a quick test with `ffmpeg` on a problematic file and loaded it in to Quik, it works 🥹
  * Came up with a quick loop to fix all the videos:
    ```
    for i in $(find . -type f -name 'GH0117*MP4'); do
      ffmpeg -hide_banner -i "$i" -c copy "$i.new.MP4" && \
      mv "$i.new.MP4" "$i" && \
      chown u0_a212:u0_a212 "$i"
    done
    ```
    (find command includes name just to limit the blast radius and duration of processing)

# Conclusion

I later realised that it's unlikely many people would have this problem, despite it being around for [at least the last 6 months](https://community.gopro.com/s/question/0D53b000091fH9dCAE/i-upgraded-quik-app-today?language=en_US). This is because having the incorrect date is fixed by connecting to the app, and it's only the GoPro Quik app that has an issue with these files.

This incident reminded me why I love Linux, free open source and having real ownership over my own device - having this kind of flexibility means you can do some cool and unusual things to work around issues, particular vendor ones.
