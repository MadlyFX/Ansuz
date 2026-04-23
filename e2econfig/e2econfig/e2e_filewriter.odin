package e2econfig

import "core:fmt"
import "core:strings"

Save_E2E_Config :: proc() {

    b := strings.builder_make()
    output_json_str := "{\n"
    strings.write_string(&b, output_json_str)
    strings.write_string(&b, fmt.aprintf("  \"type\": \"%s\",\n", E2E_Type_Names[selected_e2e_type]))

    Add_Json_Network(&output_json_str, &b)

    #partial switch selected_e2e_type{
    case .E2E_FIZ:
        Add_Json_WiFi(&output_json_str, &b)
        Add_Json_LONET(&output_json_str, &b)
    case .E2E_FIZ_PRO:
        Add_Json_WiFi(&output_json_str, &b)
        Add_Json_OTIO(&output_json_str, &b)
        Add_Json_Pro(&output_json_str, &b)
    }
    Add_Json_OSC(&output_json_str, &b)//Has no tailing comma, do not remove

    strings.write_string(&b, "}\n")

    _, err := strings.builder_replace_all(&b, "\x00", "")

    fmt.println("Error replacing null characters:", err)

    rtr := strings.to_string(b)
    fmt.println("Generated JSON:\n", rtr)

    out_string = rtr
    e2e_save_file()

    fmt.println("Configuration saved.")
}


Add_Json_Network :: proc (output_str: ^string, b: ^strings.Builder) {
    strings.write_string(b, fmt.aprintf("    \"name\": \"%s\",\n", e2e_obj.network.name))
    strings.write_string(b, fmt.aprintf("    \"ip_address\": \"%s\",\n", e2e_obj.network.ip_address))
    strings.write_string(b, fmt.aprintf("    \"subnet\": \"%s\",\n", e2e_obj.network.subnet))
    strings.write_string(b, fmt.aprintf("    \"gateway\": \"%s\",\n", e2e_obj.network.gateway))
    strings.write_string(b, fmt.aprintf("    \"dns\": \"%s\",\n", e2e_obj.network.dns))
    strings.write_string(b, fmt.aprintf("    \"dhcp\": %v,\n", e2e_obj.network.dhcp))
    strings.write_string(b, fmt.aprintf("    \"output_rate\": %d,\n", e2e_obj.network.output_rate))
    strings.write_string(b, fmt.aprintf("    \"ntp_server\": \"%s\",\n", e2e_obj.network.ntp_server))
}

Add_Json_OSC :: proc(output_json: ^string, b: ^strings.Builder) {
    strings.write_string(b, fmt.aprintf("    \"osc\": %v,\n", e2e_obj.osc.osc))
    strings.write_string(b, fmt.aprintf("    \"osc_ip_address\": \"%s\",\n", e2e_obj.osc.osc_ip_address))
    strings.write_string(b, fmt.aprintf("    \"osc_port\": %d,\n", e2e_obj.osc.osc_port))
    strings.write_string(b, fmt.aprintf("    \"osc_as_float\": %v\n", e2e_obj.osc.osc_as_float))
}

Add_Json_LONET :: proc(output_json: ^string, b: ^strings.Builder) {
    strings.write_string(b, fmt.aprintf("    \"lonet2\": %v,\n", e2e_obj.lonet.lonet2))
    strings.write_string(b, fmt.aprintf("    \"lonet2_ip_address\": \"%s\",\n", e2e_obj.lonet.lonet2_ip_address))
    strings.write_string(b, fmt.aprintf("    \"lonet2_port\": %d,\n", e2e_obj.lonet.lonet2_port))
    strings.write_string(b, fmt.aprintf("    \"lonet_multicast\": %v,\n", e2e_obj.lonet.lonet_multicast))
}

Add_Json_WiFi :: proc(output_json: ^string, b: ^strings.Builder) {
    strings.write_string(b, fmt.aprintf("    \"wifi\": %v,\n", e2e_obj.wifi.wifi))
    strings.write_string(b, fmt.aprintf("    \"wifi_ssid\": \"%s\",\n", e2e_obj.wifi.wifi_ssid))
    strings.write_string(b, fmt.aprintf("    \"wifi_password\": \"%s\",\n", e2e_obj.wifi.wifi_password))
}

Add_Json_OTIO :: proc(output_json: ^string, b: ^strings.Builder) {
    strings.write_string(b, fmt.aprintf("    \"otio\": %v,\n", e2e_obj.otio.otio))
    strings.write_string(b, fmt.aprintf("    \"otio_ip_address\": \"%s\",\n", e2e_obj.otio.otio_ip_address))
    strings.write_string(b, fmt.aprintf("    \"otio_port\": %d,\n", e2e_obj.otio.otio_port))
    strings.write_string(b, fmt.aprintf("    \"otio_multicast\": %v,\n", e2e_obj.otio.otio_multicast))
}

Add_Json_Pro :: proc(output_json: ^string, b: ^strings.Builder) {
    strings.write_string(b, fmt.aprintf("    \"flip_display\": %v,\n", e2e_obj.flipDisplay))
    strings.write_string(b, fmt.aprintf("    \"genlock_multiplier\": %v,\n", e2e_obj.genlock_multiplier))
    strings.write_string(b, fmt.aprintf("    \"enable_data_logging\": %v,\n", e2e_obj.enableDataLogging))
    strings.write_string(b, fmt.aprintf("    \"protocol\": \"%v\",\n", strings.to_lower(string(e2e_obj.protocol))))
    strings.write_string(b, fmt.aprintf("    \"lens_double_powerup_string\": %v,\n", e2e_obj.lensDoublePowerupString))
    strings.write_string(b, fmt.aprintf("    \"lens_is_metric\": %v,\n", e2e_obj.lensIsMetric))
}