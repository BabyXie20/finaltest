set_global_assignment -entity "MIPI_PLL" -library "lib_MIPI_PLL" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "MIPI_PLL" -library "lib_MIPI_PLL" -name IP_TOOL_VERSION "16.1"
set_global_assignment -entity "MIPI_PLL" -library "lib_MIPI_PLL" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_MIPI_PLL" -name SPD_FILE [file join $::quartus(sip_path) "MIPI_PLL.spd"]

set_global_assignment -library "lib_MIPI_PLL" -name MISC_FILE [file join $::quartus(sip_path) "MIPI_PLL_sim/MIPI_PLL.vo"]
