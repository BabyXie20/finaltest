set_global_assignment -entity "SDRAM_PLL" -library "lib_SDRAM_PLL" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "SDRAM_PLL" -library "lib_SDRAM_PLL" -name IP_TOOL_VERSION "16.1"
set_global_assignment -entity "SDRAM_PLL" -library "lib_SDRAM_PLL" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_SDRAM_PLL" -name SPD_FILE [file join $::quartus(sip_path) "SDRAM_PLL.spd"]

set_global_assignment -library "lib_SDRAM_PLL" -name MISC_FILE [file join $::quartus(sip_path) "SDRAM_PLL_sim/SDRAM_PLL.vo"]
