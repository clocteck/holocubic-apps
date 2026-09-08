# Radio 0.1.4 branding

Generated using the built-in imagegen tool, not API/CLI mode.
Selected original: `src/assets/radio-logo-transparent-original.png`.
Launcher export: `package/main.png`, 128×128 PNG.
The export only resizes the generated artwork and preserves its alpha channel;
it does not redraw the icon. The user selected the first, transparent generation.
The previous opaque icon is retained as `src/assets/radio-logo-black-128.png`.
`package/info.html` embeds the icon and needs no external fonts or libraries.
Editable page source: `src/web/info.template.html`.

Final generation/edit prompt:

> Edit this Radio app icon. Preserve the recognizable radio silhouette, antenna,
> three horizontal speaker holes and circular knob, and centered composition.
> Correct ONLY the finish to truly flat graphic design: remove ALL yellow speckles,
> mottling, glow, texture and gradients. Every background and speaker hole pixel
> should be solid black, and the radio should be one uniform flat warm amber
> #FFA857, with clean antialiased edges. Increase empty margins slightly to 20
> percent around the symbol. A single minimal Apple-style flat pictogram, no text,
> no mockup. Deliver a small square app icon, preferably 128x128 PNG for an embedded
> device launcher.

The generated master was larger than requested, so the packaging script exports
a small launcher asset to avoid loading the full-resolution master on the device.
The final image is an original radio pictogram, not an Apple logo.

The independent Radio Audio Restore helper was removed at the user's request.
The App no longer auto-stops or restores XiaoZhi/AirPlay; users manage competing
audio services manually. Archived helper source is not included in deployment.
