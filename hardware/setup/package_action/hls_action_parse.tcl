#-----------------------------------------------------------
#
# Copyright 2016-2020, International Business Machines
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#-----------------------------------------------------------

package require json
set kernel_name          $::env(KERNEL_NAME)
set hls_support          $::env(HLS_SUPPORT)
set action_hw_dir        $::env(ACTION_ROOT)/hw
set action_sw_dir        $::env(ACTION_ROOT)/sw
set action_hls_dir       $action_hw_dir/hls
set register_layout_file $action_sw_dir/hls_${kernel_name}_register_layout.h

# find the JSON file
if {$hls_support != TRUE} {
    puts "HLS is not enabled, unable to run hls action parsing!"
    exit -1
}

set json_files [exec find $action_hls_dir -name ${kernel_name}_data.json]

if {[llength $json_files] != 1} {
    puts "Only 1 JSON file should be found, but why not?"
    puts "The file(s) found: $json_files"
    exit -1
}

# read the JSON file as a dict
set json_dict [json::json2dict [read [open [lindex $json_files 0] r]]]

# Parse the interface information
if {! [dict exists $json_dict Interfaces] } {
    puts "No Interfaces found in the JSON file!"
    exit -1
}

set interfaces [dict get $json_dict Interfaces]

set kernel_axi_masters {}
set kernel_axilite_slaves {}
set kernel_clock_pin_name ""
set kernel_reset_pin_name ""
set kernel_axilite_name ""
set kernel_axilite_addr_width ""
foreach intf [dict keys $interfaces] {
    set value [dict get $interfaces $intf]
    set type [dict get $value type]
    puts [format "Found interface name %15s | type %15s" $intf $type]

    if {"native_axim" == $type} {
        set mode [dict get $value mode]
        if {"master" == $mode} {
            lappend kernel_axi_masters $value
        }
    }

    if {"axi4lite" == $type} {
        set mode [dict get $value mode]
        if {"slave" == $mode} {
            lappend kernel_axilite_slaves $value
        }
    }

    if {"clock" == $type} {
        set kernel_clock_pin_name $intf
    }

    if {"reset" == $type} {
        set kernel_reset_pin_name $intf
    }
}

set num_kernel_axi_masters [llength $kernel_axi_masters]
set num_kernel_axilite_slaves [llength $kernel_axilite_slaves]

puts "$kernel_name has $num_kernel_axi_masters AXI masters, $num_kernel_axilite_slaves AXILite slaves"

if {$num_kernel_axilite_slaves != 1} {
    puts "You need to have at least 1 and only 1 AXILite slave interface!"
    exit -1
}

# get registers
set axilite [lindex $kernel_axilite_slaves 0]
if {! [dict exists $axilite registers]} {
    puts "WARNING: no registers defined for AXILite slave interface, no register layout header file will be generated!"
} else {
    set fp [open $register_layout_file w+]
    puts $fp "// ---- AUTO GENERATED! DO NOT EDIT! ----"
    puts $fp "struct register_layout {"
    set registers [dict get $axilite registers]
    foreach reg $registers {
        set reg_name [dict get $reg name]
        set reg_offset [dict get $reg offset]
        puts $fp "    uint32_t $reg_name = $reg_offset;"
    }

    puts $fp "}; /* register_layout */"
    puts "$register_layout_file is successfully generated."

    set prefix [dict get $axilite port_prefix]
    set kernel_axilite_name $prefix

    set addr_width [dict get $axilite addr_bits]
    set kernel_axilite_addr_width $addr_width
}

