package e2econfig

import "core:fmt"
import ansuz "../../ansuz"

// Section visibility states (replaces imgui collapsing headers)
section_network_open: bool = true
section_protocol_open: bool = false
section_lonet_open: bool = false
section_osc_open: bool = false
section_wifi_open: bool = false
section_otio_open: bool = false

// Dropdown indices
e2e_type_idx: int = 0
protocol_idx: int = 0

// Text input buffers (ansuz text_input requires [dynamic]u8)
buf_name: [dynamic]u8
buf_net_ip: [dynamic]u8
buf_net_subnet: [dynamic]u8
buf_net_gateway: [dynamic]u8
buf_net_dns: [dynamic]u8
buf_lonet_ip: [dynamic]u8
buf_osc_ip: [dynamic]u8
buf_wifi_ssid: [dynamic]u8
buf_wifi_pass: [dynamic]u8
buf_otio_ip: [dynamic]u8
buf_ntp_server: [dynamic]u8

// Float wrappers for i32 slider values
f_output_rate: f32
f_lonet_port: f32
f_osc_port: f32
f_otio_port: f32
f_genlock_multiplier: f32

gui_mgr:    ^ansuz.Manager
font_regular: ansuz.Font_Handle
font_bold:    ansuz.Font_Handle

e2e_type_options := [?]string{"E2E FIZ PRO", "E2E FIZ", "E2E"}
protocol_options := [?]string{"Auto", "Encoders", "Cooke /i", "Zeiss XD"}

Save_File :: proc() -> bool
e2e_save_file: Save_File

out_string: string

Init_Gui :: proc(manager: ^ansuz.Manager, save_file_callback: Save_File, regular: ansuz.Font_Handle, bold: ansuz.Font_Handle) {
	gui_mgr = manager
	font_regular = regular
	font_bold = bold
	e2e_save_file = save_file_callback
	Initialize_E2E_Objs()
	sync_buffers_from_config()
}

Shutdown_Gui :: proc() {
	delete(buf_name)
	delete(buf_net_ip)
	delete(buf_net_subnet)
	delete(buf_net_gateway)
	delete(buf_net_dns)
	delete(buf_lonet_ip)
	delete(buf_osc_ip)
	delete(buf_wifi_ssid)
	delete(buf_wifi_pass)
	delete(buf_otio_ip)
	delete(buf_ntp_server)
}

// --- Buffer Sync ---

@(private)
copy_fixed_to_dynamic :: proc(buf: ^[dynamic]u8, src: []byte) {
	clear(buf)
	for b in src {
		if b == 0 do break
		append(buf, b)
	}
}

@(private)
copy_dynamic_to_fixed :: proc(dst: []byte, src: []u8) {
	for i in 0 ..< len(dst) {
		dst[i] = src[i] if i < len(src) else 0
	}
}

sync_buffers_from_config :: proc() {
	copy_fixed_to_dynamic(&buf_name, e2e_obj.network.name[:])
	copy_fixed_to_dynamic(&buf_net_ip, e2e_obj.network.ip_address[:])
	copy_fixed_to_dynamic(&buf_net_subnet, e2e_obj.network.subnet[:])
	copy_fixed_to_dynamic(&buf_net_gateway, e2e_obj.network.gateway[:])
	copy_fixed_to_dynamic(&buf_net_dns, e2e_obj.network.dns[:])
	copy_fixed_to_dynamic(&buf_lonet_ip, e2e_obj.lonet.lonet2_ip_address[:])
	copy_fixed_to_dynamic(&buf_osc_ip, e2e_obj.osc.osc_ip_address[:])
	copy_fixed_to_dynamic(&buf_wifi_ssid, e2e_obj.wifi.wifi_ssid[:])
	copy_fixed_to_dynamic(&buf_wifi_pass, e2e_obj.wifi.wifi_password[:])
	copy_fixed_to_dynamic(&buf_otio_ip, e2e_obj.otio.otio_ip_address[:])
	copy_fixed_to_dynamic(&buf_ntp_server, e2e_obj.network.ntp_server[:])

	f_output_rate         = f32(e2e_obj.network.output_rate)
	f_lonet_port          = f32(e2e_obj.lonet.lonet2_port)
	f_osc_port            = f32(e2e_obj.osc.osc_port)
	f_otio_port           = f32(e2e_obj.otio.otio_port)
	f_genlock_multiplier  = f32(e2e_obj.genlock_multiplier)

	e2e_type_idx = int(selected_e2e_type)
	for i in 0 ..< len(Pro_Protocol_Names) {
		if e2e_obj.protocol == Pro_Protocol_Names[i] {
			protocol_idx = i
			break
		}
	}
}

sync_buffers_to_config :: proc() {
	copy_dynamic_to_fixed(e2e_obj.network.name[:], buf_name[:])
	copy_dynamic_to_fixed(e2e_obj.network.ip_address[:], buf_net_ip[:])
	copy_dynamic_to_fixed(e2e_obj.network.subnet[:], buf_net_subnet[:])
	copy_dynamic_to_fixed(e2e_obj.network.gateway[:], buf_net_gateway[:])
	copy_dynamic_to_fixed(e2e_obj.network.dns[:], buf_net_dns[:])
	copy_dynamic_to_fixed(e2e_obj.lonet.lonet2_ip_address[:], buf_lonet_ip[:])
	copy_dynamic_to_fixed(e2e_obj.osc.osc_ip_address[:], buf_osc_ip[:])
	copy_dynamic_to_fixed(e2e_obj.wifi.wifi_ssid[:], buf_wifi_ssid[:])
	copy_dynamic_to_fixed(e2e_obj.wifi.wifi_password[:], buf_wifi_pass[:])
	copy_dynamic_to_fixed(e2e_obj.otio.otio_ip_address[:], buf_otio_ip[:])
	copy_dynamic_to_fixed(e2e_obj.network.ntp_server[:], buf_ntp_server[:])

	e2e_obj.network.output_rate  = i32(f_output_rate)
	e2e_obj.lonet.lonet2_port    = i32(f_lonet_port)
	e2e_obj.osc.osc_port         = i32(f_osc_port)
	e2e_obj.otio.otio_port       = i32(f_otio_port)
	e2e_obj.genlock_multiplier   = i32(f_genlock_multiplier)

	e2e_obj.protocol = Pro_Protocol_Names[protocol_idx]
}

// --- UI Helpers ---

HEADER_COLOR :: ansuz.Widget_Color{
	bg    = ansuz.Color{36, 61, 89, 255},
	fg    = ansuz.THEME_TEXT,
	hover = ansuz.Color{59, 102, 150, 255},
	press = ansuz.THEME_BG_BUTTON_ACTIVE,
}

BUTTON_COLOR :: ansuz.Widget_Color{
	bg    = ansuz.Color{0, 51, 181, 255},
	fg    = ansuz.THEME_TEXT,
	hover = ansuz.Color{36, 89, 224, 255},
	press = ansuz.THEME_BG_BUTTON_ACTIVE,
}

@(private)
section_header :: proc(text: string, open: ^bool) {
	ansuz.push_id(gui_mgr, text)
	arrow := "v " if open^ else "> "
	if .Clicked in ansuz.button(gui_mgr, fmt.tprintf("%s%s", arrow, text), scale = 2.5, color = HEADER_COLOR, font = font_bold) {
		open^ = !open^
	}
	ansuz.pop_id(gui_mgr)
}

@(private)
labeled_text_field :: proc(label_text: string, buf: ^[dynamic]u8, width: f32 = 200) {
	ansuz.push_id(gui_mgr, label_text)
	ansuz.flex_begin(gui_mgr, axis = .Horizontal, gap = 8, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center)
	ansuz.label(gui_mgr, label_text, font = font_regular, size = {ansuz.size_fixed(120), ansuz.SIZE_FIT})
	ansuz.text_input(gui_mgr, buf, font = font_regular, size = {ansuz.size_fixed(width), ansuz.SIZE_FIT})
	ansuz.flex_end(gui_mgr)
	ansuz.pop_id(gui_mgr)
}

// --- Main Draw ---

Draw_Gui :: proc() {
	ansuz.scroll_begin(gui_mgr, gap = 10, size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW}, padding = {12, 16, 12, 16})

	// Header: E2E type selector + action buttons
	ansuz.flex_begin(gui_mgr, axis = .Horizontal, gap = 8, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center, bg_color = ansuz.THEME_BG_BUTTON_ACTIVE)
	ansuz.dropdown(gui_mgr, &e2e_type_idx, e2e_type_options[:])
	selected_e2e_type = E2E_TYPE(e2e_type_idx)
	if .Clicked in ansuz.button(gui_mgr, "Reset Settings", color = BUTTON_COLOR) {
		Set_Default_E2E_Values()
		sync_buffers_from_config()
	}
	if .Clicked in ansuz.button(gui_mgr, "Save Config", color = BUTTON_COLOR) {
		sync_buffers_to_config()
		Save_E2E_Config()
	}
	ansuz.flex_end(gui_mgr)

	// Separator
	ansuz.box(gui_mgr, size = {ansuz.SIZE_GROW, ansuz.size_fixed(1)}, bg_color = ansuz.THEME_BORDER)

	Draw_Network_Section()

	switch selected_e2e_type {
	case .E2E:
		Draw_LONET_Section()
	case .E2E_FIZ:
		Draw_WiFi_Section()
		Draw_LONET_Section()
	case .E2E_FIZ_PRO:
		Draw_Protocol_Section()
		Draw_WiFi_Section()
		Draw_OTIO_Section()
	}

	Draw_OSC_Section()

	ansuz.scroll_end(gui_mgr)
}

// --- Sections ---

Draw_Protocol_Section :: proc() {
	section_header("Protocol", &section_protocol_open)
	if section_protocol_open {
		ansuz.flex_begin(gui_mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, padding = {0, 0, 0, 16})

		ansuz.flex_begin(gui_mgr, axis = .Horizontal, gap = 8, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center)
		ansuz.label(gui_mgr, "Protocol", font = font_regular, size = {ansuz.size_fixed(120), ansuz.SIZE_FIT})
		ansuz.dropdown(gui_mgr, &protocol_idx, protocol_options[:])
		ansuz.flex_end(gui_mgr)
		e2e_obj.protocol = Pro_Protocol_Names[protocol_idx]

		if protocol_idx != 1 {
			ansuz.checkbox(gui_mgr, "Lens is Metric", &e2e_obj.lensIsMetric, font = font_regular)
			ansuz.checkbox(gui_mgr, "Lens Double Powerup String", &e2e_obj.lensDoublePowerupString, font = font_regular)
			ansuz.label(gui_mgr, "Some XD lenses may need this enabled", color = ansuz.Label_Color{label = ansuz.THEME_TEXT_DIM}, font = font_regular)
		}

		ansuz.flex_end(gui_mgr)
	}
}

Draw_Network_Section :: proc() {
	section_header("Network", &section_network_open)
	if section_network_open {
		ansuz.flex_begin(gui_mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, padding = {0, 0, 0, 16})

		labeled_text_field("E2E Name", &buf_name)
		ansuz.slider_labeled(gui_mgr, "Output Rate", font_regular, value = &f_output_rate, lo = 1, hi = 120, format = "%.0f")
		ansuz.slider_labeled(gui_mgr, "Genlock Multiplier", font_regular, value = &f_genlock_multiplier, lo = 1, hi = 16, format = "%.0f")
		ansuz.checkbox(gui_mgr, "Flip Display", &e2e_obj.flipDisplay, font = font_regular)
		ansuz.checkbox(gui_mgr, "Enable Data Logging", &e2e_obj.enableDataLogging, font = font_regular)
		labeled_text_field("NTP Server", &buf_ntp_server, 200)
		ansuz.checkbox(gui_mgr, "DHCP", &e2e_obj.network.dhcp, font = font_regular)

		if !e2e_obj.network.dhcp {
			labeled_text_field("IP Address", &buf_net_ip)
			labeled_text_field("Subnet", &buf_net_subnet)
			labeled_text_field("Gateway", &buf_net_gateway)
			labeled_text_field("DNS", &buf_net_dns)
		}

		ansuz.flex_end(gui_mgr)
	}
}

Draw_LONET_Section :: proc() {
	section_header("LONET", &section_lonet_open)
	if section_lonet_open {
		ansuz.flex_begin(gui_mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, padding = {0, 0, 0, 16})

		ansuz.checkbox(gui_mgr, "LONET2", &e2e_obj.lonet.lonet2, font = font_regular)
		if e2e_obj.lonet.lonet2 {
			labeled_text_field("IP Address", &buf_lonet_ip)
			ansuz.slider_labeled(gui_mgr, "Port", font_regular, value = &f_lonet_port, lo = 1, hi = 65535, format = "%.0f")
			ansuz.checkbox(gui_mgr, "LONET Multicast", &e2e_obj.lonet.lonet_multicast, font = font_regular)
		}

		ansuz.flex_end(gui_mgr)
	}
}

Draw_OSC_Section :: proc() {
	section_header("OSC", &section_osc_open)
	if section_osc_open {
		ansuz.flex_begin(gui_mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, padding = {0, 0, 0, 16})

		ansuz.checkbox(gui_mgr, "OSC", &e2e_obj.osc.osc, font = font_regular)
		if e2e_obj.osc.osc {
			labeled_text_field("IP Address", &buf_osc_ip)
			ansuz.slider_labeled(gui_mgr, "Port", font_regular, value = &f_osc_port, lo = 1, hi = 65535, format = "%.0f")
			ansuz.checkbox(gui_mgr, "OSC as Float", &e2e_obj.osc.osc_as_float, font = font_regular)
		}

		ansuz.flex_end(gui_mgr)
	}
}

Draw_WiFi_Section :: proc() {
	section_header("WiFi", &section_wifi_open)
	if section_wifi_open {
		ansuz.flex_begin(gui_mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, padding = {0, 0, 0, 16})

		ansuz.checkbox(gui_mgr, "WiFi", &e2e_obj.wifi.wifi, font = font_regular)
		if e2e_obj.wifi.wifi {
			labeled_text_field("SSID", &buf_wifi_ssid)
			labeled_text_field("Password", &buf_wifi_pass)
		}

		ansuz.flex_end(gui_mgr)
	}
}

Draw_OTIO_Section :: proc() {
	section_header("OpenTrackIO", &section_otio_open)
	if section_otio_open {
		ansuz.flex_begin(gui_mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, padding = {0, 0, 0, 16})

		ansuz.checkbox(gui_mgr, "Enable OTIO", &e2e_obj.otio.otio, font = font_regular)
		if e2e_obj.otio.otio {
			labeled_text_field("IP Address", &buf_otio_ip)
			ansuz.slider_labeled(gui_mgr, "Port", font_regular, value = &f_otio_port, lo = 1, hi = 65535, format = "%.0f")
			ansuz.checkbox(gui_mgr, "Multicast", &e2e_obj.otio.otio_multicast, font = font_regular)
		}

		ansuz.flex_end(gui_mgr)
	}
}
