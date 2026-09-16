# 图标资源

- `icon-source.png`：用户提供的原始图片，保留不改。
- `icon-transparent.png`：使用内置 image_gen（imagegen 技能）做背景提取得到的透明 PNG。
- `../build_icon.ps1`：缩放生成设备 `main.png`，保留 PNG Alpha，并更新 info.html 的 Base64；启动 BMP 按应用黑底合成，避免再次解码大图。
- 原图主体和内部白色标志需保留，只去除外围白色/浅灰背景。

## 使用的完整提示词

Use case: background-extraction. Edit target: the supplied QQ Music icon. Remove ONLY the white/light-gray background outside the yellow circular disc and green musical note, including the outer white rounded-square tile. Make all that exterior genuinely transparent with alpha, not a checkerboard or a painted background. Preserve the yellow disc, green/turquoise note, their original shape, proportions, gradients and positions exactly. Preserve original square framing and margins. Clean antialiased edges without white halos. No redesign, no text, no shadow, no new elements. Output a transparent PNG.
