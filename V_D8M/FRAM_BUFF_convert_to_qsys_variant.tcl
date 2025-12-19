package require -exact qsys 14.0
create_system FRAM_BUFF
add_instance FRAM_BUFF ram_2port
set_instance_property FRAM_BUFF AUTO_EXPORT true
set param_pairs [list]
lappend param_pairs {DEVICE_FAMILY} {Arria 10}
lappend param_pairs {GUI_MODE} {1}
lappend param_pairs {GUI_MEM_IN_BITS} {0}
lappend param_pairs {GUI_MEMSIZE_WORDS} {307200}
lappend param_pairs {GUI_QA_WIDTH} {10}
lappend param_pairs {GUI_QB_WIDTH} {10}
lappend param_pairs {GUI_DATAA_WIDTH} {10}
lappend param_pairs {GUI_MAX_DEPTH} {Auto}
lappend param_pairs {GUI_VAR_WIDTH} {0}
lappend param_pairs {GUI_RAM_BLOCK_TYPE} {Auto}
lappend param_pairs {GUI_LC_IMPLEMENTION_OPTIONS} {0}
lappend param_pairs {GUI_CLOCK_TYPE} {4}
lappend param_pairs {GUI_RDEN_SINGLE} {0}
lappend param_pairs {GUI_RDEN_DOUBLE} {0}
lappend param_pairs {GUI_BYTE_ENABLE_A} {0}
lappend param_pairs {GUI_BYTE_ENABLE_B} {0}
lappend param_pairs {GUI_BYTE_ENABLE_WIDTH} {8}
lappend param_pairs {GUI_READ_INPUT_RDADDRESS} {1}
lappend param_pairs {GUI_READ_OUTPUT_QA} {0}
lappend param_pairs {GUI_READ_OUTPUT_QB} {0}
lappend param_pairs {GUI_DIFFERENT_CLKENS} {0}
lappend param_pairs {GUI_CLKEN_WRITE_INPUT_REG} {0}
lappend param_pairs {GUI_CLKEN_READ_INPUT_REG} {0}
lappend param_pairs {GUI_CLKEN_READ_OUTPUT_REG} {0}
lappend param_pairs {GUI_CLKEN_INPUT_REG_A} {0}
lappend param_pairs {GUI_CLKEN_INPUT_REG_B} {0}
lappend param_pairs {GUI_CLKEN_OUTPUT_REG_A} {0}
lappend param_pairs {GUI_CLKEN_OUTPUT_REG_B} {0}
lappend param_pairs {GUI_CLKEN_ADDRESS_STALL_A} {0}
lappend param_pairs {GUI_CLKEN_ADDRESS_STALL_B} {0}
lappend param_pairs {GUI_CLKEN_WRADDRESSSTALL} {0}
lappend param_pairs {GUI_CLKEN_RDADDRESSSTALL} {0}
lappend param_pairs {GUI_ACLR_READ_INPUT_RDADDRESS} {0}
lappend param_pairs {GUI_ACLR_READ_OUTPUT_QA} {0}
lappend param_pairs {GUI_ACLR_READ_OUTPUT_QB} {0}
lappend param_pairs {GUI_Q_PORT_MODE} {2}
lappend param_pairs {GUI_RDW_A_MODE} {New Data}
lappend param_pairs {GUI_RDW_B_MODE} {New Data}
lappend param_pairs {GUI_NBE_A} {TRUE}
lappend param_pairs {GUI_NBE_B} {TRUE}
lappend param_pairs {GUI_BLANK_MEMORY} {0}
lappend param_pairs {GUI_INIT_FILE_LAYOUT} {PORT_A}
lappend param_pairs {GUI_INIT_SIM_TO_X} {0}
foreach {param_name param_value} $param_pairs {
    set sys_info_type [get_instance_parameter_property FRAM_BUFF "$param_name" SYSTEM_INFO_TYPE]
    if {$sys_info_type == "DEVICE_FAMILY"} {
        set_project_property DEVICE_FAMILY "$param_value"
        break;
    }
}
foreach {param_name param_value} $param_pairs {
    set_instance_parameter_value FRAM_BUFF "$param_name" "$param_value"
}
save_system {D:/Home/User/Desktop/DE10_Nano/RTL/D8M/0_0_DE10_NANO_D8MGPIO0_RAM_RTL/V_D8M/FRAM_BUFF.qsys}
