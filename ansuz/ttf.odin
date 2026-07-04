#+build !freestanding
package ansuz

// --- TrueType Font Loading ---
// Rasterizes TTF font data into a grayscale coverage atlas using stb_truetype.
// SDL and WebGL upload this alpha atlas to GPU textures for antialiased text.

import stbtt "vendor:stb/truetype"

// Load a TrueType font from raw font file data and rasterize it into an atlas.
// pixel_size: the height in pixels to rasterize glyphs at.
// extra_codepoints: optional slice of Unicode codepoints (> 255) to bake into
//   the atlas. Pass FONT_EXTRA_CODEPOINTS[:] for common UI symbols.
// Returns the Font and true on success, or an empty Font and false on failure.
load_font_from_data :: proc(ttf_data: []u8, pixel_size: f32, extra_codepoints: []rune = nil) -> (Font, bool) {
	font: Font
	font.kind = .Atlas
	font.pixel_size = pixel_size
	font.scale_norm = f32(FONT_GLYPH_HEIGHT) / pixel_size
	font.antialiasing = .Grayscale
	font.oversample_x = u8(FONT_TTF_OVERSAMPLE_X)
	font.oversample_y = u8(FONT_TTF_OVERSAMPLE_Y)

	// Oversampled fonts need more atlas space than 1x packed bitmaps.
	atlas_w, atlas_h := ttf_atlas_size(pixel_size, len(extra_codepoints))
	font.atlas_width = atlas_w
	font.atlas_height = atlas_h
	font.atlas_pixels = make([]u8, int(atlas_w * atlas_h))

	FIRST_ASCII :: i32(32)
	NUM_ASCII   :: i32(96)   // 32-127
	FIRST_EXT   :: i32(128)
	NUM_EXT     :: i32(128)  // 128-255

	chardata_ascii: [NUM_ASCII]stbtt.packedchar
	chardata_ext:   [NUM_EXT]stbtt.packedchar

	n_extra := len(extra_codepoints)
	chardata_extra := make([]stbtt.packedchar, max(n_extra, 1))
	defer delete(chardata_extra)

	ranges: [dynamic]stbtt.pack_range
	defer delete(ranges)

	append(&ranges, stbtt.pack_range{
		font_size                        = pixel_size,
		first_unicode_codepoint_in_range = FIRST_ASCII,
		num_chars                        = NUM_ASCII,
		chardata_for_range               = raw_data(chardata_ascii[:]),
	})
	append(&ranges, stbtt.pack_range{
		font_size                        = pixel_size,
		first_unicode_codepoint_in_range = FIRST_EXT,
		num_chars                        = NUM_EXT,
		chardata_for_range               = raw_data(chardata_ext[:]),
	})
	if n_extra > 0 {
		append(&ranges, stbtt.pack_range{
			font_size                    = pixel_size,
			array_of_unicode_codepoints  = raw_data(extra_codepoints),
			num_chars                    = i32(n_extra),
			chardata_for_range           = raw_data(chardata_extra),
		})
	}

	spc: stbtt.pack_context
	if stbtt.PackBegin(&spc, raw_data(font.atlas_pixels), atlas_w, atlas_h, 0, FONT_TTF_ATLAS_PADDING, nil) == 0 {
		delete(font.atlas_pixels)
		return {}, false
	}
	stbtt.PackSetOversampling(&spc, FONT_TTF_OVERSAMPLE_X, FONT_TTF_OVERSAMPLE_Y)

	pack_result := stbtt.PackFontRanges(&spc, raw_data(ttf_data), 0, raw_data(ranges[:]), i32(len(ranges)))
	stbtt.PackEnd(&spc)

	if pack_result == 0 {
		delete(font.atlas_pixels)
		return {}, false
	}

	// Extract ASCII glyph metrics (32-127)
	for i in 0..<int(NUM_ASCII) {
		ch := &chardata_ascii[i]
		idx := int(FIRST_ASCII) + i
		font.glyphs[idx] = Font_Glyph_Info{
			atlas_x  = ch.x0,
			atlas_y  = ch.y0,
			atlas_w  = ch.x1 - ch.x0,
			atlas_h  = ch.y1 - ch.y0,
			x_offset = ch.xoff,
			y_offset = ch.yoff,
			x_offset2 = ch.xoff2,
			y_offset2 = ch.yoff2,
			advance  = ch.xadvance,
		}
	}

	// Extract extended ASCII glyph metrics (128-255)
	for i in 0..<int(NUM_EXT) {
		ch := &chardata_ext[i]
		idx := int(FIRST_EXT) + i
		font.glyphs[idx] = Font_Glyph_Info{
			atlas_x  = ch.x0,
			atlas_y  = ch.y0,
			atlas_w  = ch.x1 - ch.x0,
			atlas_h  = ch.y1 - ch.y0,
			x_offset = ch.xoff,
			y_offset = ch.yoff,
			x_offset2 = ch.xoff2,
			y_offset2 = ch.yoff2,
			advance  = ch.xadvance,
		}
	}

	// Extract extra Unicode glyph metrics
	if n_extra > 0 {
		font.glyphs_unicode = make(map[rune]Font_Glyph_Info, n_extra)
		for i in 0..<n_extra {
			ch := &chardata_extra[i]
			font.glyphs_unicode[extra_codepoints[i]] = Font_Glyph_Info{
				atlas_x  = ch.x0,
				atlas_y  = ch.y0,
				atlas_w  = ch.x1 - ch.x0,
				atlas_h  = ch.y1 - ch.y0,
				x_offset = ch.xoff,
				y_offset = ch.yoff,
				x_offset2 = ch.xoff2,
				y_offset2 = ch.yoff2,
				advance  = ch.xadvance,
			}
		}
	}

	// Get font vertical metrics for proper baseline positioning
	info: stbtt.fontinfo
	if !stbtt.InitFont(&info, raw_data(ttf_data), 0) {
		delete(font.atlas_pixels)
		delete(font.glyphs_unicode)
		return {}, false
	}

	ascent, descent, line_gap: i32
	stbtt.GetFontVMetrics(&info, &ascent, &descent, &line_gap)
	fscale := stbtt.ScaleForPixelHeight(&info, pixel_size)

	font.ascent = f32(ascent) * fscale
	font.line_height = f32(ascent - descent + line_gap) * fscale

	return font, true
}

ttf_atlas_size :: proc(pixel_size: f32, extra_count: int) -> (i32, i32) {
	if pixel_size >= 64 {
		return 2048, 2048
	}
	if extra_count > 0 {
		return 1024, 2048
	}
	return 1024, 1024
}
