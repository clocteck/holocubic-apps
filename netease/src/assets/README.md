# 图标资源

- `icon-source.png`：用户提供的原始图片，保留不改。
- `icon-transparent.png`：使用内置 image_gen（imagegen 技能）做背景提取得到的透明 PNG。
- `../build_icon.ps1`：缩放生成设备 `main.png`，保留 PNG Alpha，并更新 info.html 的 Base64；启动 BMP 按应用黑底合成，避免再次解码大图。
- 原图主体和内部白色标志需保留，只去除外围白色/浅灰背景。

## 使用的完整提示词

Use case: background-extraction. Edit target: the supplied NetEase Cloud Music icon. Remove ONLY the light-gray/white exterior OUTSIDE the red rounded-square icon, especially the four outer corners. Make these exterior areas genuinely transparent with alpha, not a checkerboard or painted backdrop. IMPORTANT: preserve the opaque WHITE MUSIC SYMBOL inside the red square exactly; it is the logo, not background. Preserve the red rounded-square shape, original red gradient, white symbol, proportions, layout and original square framing exactly. Clean antialiased contour without white halos. No redesign, no extra margins, no text or shadows. Output a transparent PNG.
