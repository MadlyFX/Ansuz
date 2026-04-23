package e2econfig

E2E_TYPE :: enum {
	E2E_FIZ_PRO,
	E2E_FIZ,
	E2E,
}

Network_Config :: struct {
	name:              [12]byte,
	output_rate:       i32,
	dhcp:              bool,
	ip_address:        [16]byte,
	subnet:            [16]byte,
	gateway:           [16]byte,
	dns:               [16]byte,
	ntp_server:        [64]byte,
}

OSC_Config :: struct {
	osc:            bool,
	osc_ip_address: [16]byte,
	osc_port:       i32,
	osc_as_float:   bool,
}

WiFi_Config :: struct {
	wifi:          bool,
	wifi_ssid:     [32]byte,
	wifi_password: [32]byte,
}

LONET_Config :: struct {
	lonet2:            bool,
	lonet2_ip_address: [16]byte,
	lonet2_port:       i32,
	lonet_multicast:   bool,
}

OTIO_Config :: struct {
	otio: bool,
	otio_ip_address: [16]byte,
	otio_port: i32,
	otio_multicast: bool,
}

E2E_Config :: struct {
	type:    string,
	network: Network_Config,
	lonet:   LONET_Config,
	osc:     OSC_Config,
}

E2E_FIZ_Config :: struct {
	type:    string,
	network: Network_Config,
	lonet:   LONET_Config,
	osc:     OSC_Config,
	wifi:    WiFi_Config,
}

E2E_Megastruct :: struct {
	type:                    string,
	network:                 Network_Config,
	osc:                     OSC_Config,
	wifi:                    WiFi_Config,
	otio:                    OTIO_Config,
	lonet:                    LONET_Config,
	protocol:                cstring,
	lensDoublePowerupString: bool,
	lensIsMetric:            bool,
	genlock_multiplier:      i32,
	flipDisplay:             bool,
	enableDataLogging:       bool,
}


E2E_Type_Names: [3]cstring = {"E2E FIZ PRO", "E2E FIZ", "E2E"}
Pro_Protocol_Names: [4]cstring = {"Auto", "Encoders", "Cooke /i", "Zeiss XD"}

e2e_obj : E2E_Megastruct

selected_e2e_type: E2E_TYPE


Initialize_E2E_Objs :: proc() {

	Set_Default_E2E_Values()
}

Set_Default_E2E_Values :: proc() {
			e2e_obj.type = "e2e_fiz_pro"
			copy(e2e_obj.network.name[:12], "E2E Device")
			copy(e2e_obj.network.ip_address[:16], "192.168.0.100")
			copy(e2e_obj.network.subnet[:16], "255.255.255.0")
			copy(e2e_obj.network.gateway[:16], "192.168.0.1")
			copy(e2e_obj.network.dns[:16], "192.168.0.0")
			e2e_obj.network.dhcp = true
			e2e_obj.network.output_rate = 48
			e2e_obj.wifi.wifi = false
            //t.wifi.wifi_ssid = "WiFi SSID"
            //t.wifi.wifi_password = "WiFi Password"
			e2e_obj.lonet.lonet2 = true
			copy(e2e_obj.lonet.lonet2_ip_address[:16], "236.12.12.12")
			e2e_obj.lonet.lonet2_port = 60608
			e2e_obj.lonet.lonet_multicast = true
			e2e_obj.otio.otio = true
			copy(e2e_obj.otio.otio_ip_address[:16], "239.135.1.1")
			e2e_obj.otio.otio_port = 55555
			e2e_obj.otio.otio_multicast = true
			e2e_obj.osc.osc = false
			copy(e2e_obj.osc.osc_ip_address[:16], "192.168.0.255")
			e2e_obj.osc.osc_port = 8888
			e2e_obj.osc.osc_as_float = true
			e2e_obj.flipDisplay = false
			e2e_obj.genlock_multiplier = 2
			e2e_obj.enableDataLogging = false
			copy(e2e_obj.network.ntp_server[:64], "pool.ntp.org")
			e2e_obj.protocol = "Auto"
			e2e_obj.lensDoublePowerupString = false

}
