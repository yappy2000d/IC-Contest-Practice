set cycle 10          ;	#clock period defined by designer (change here only)
set t_in  [expr {$cycle / 2.0}]  ;	#input delay = half a cycle (follows cycle)
set t_out 0.5	      ;	#output delay: fixed, testfixture checks Y with an absolute 0.5 ns setup/hold


set_operating_conditions -min fast  -max slow
set_wire_load_model -name tsmc13_wl10 -library slow

create_clock -period $cycle    [get_ports clk]
set_dont_touch_network         [get_clocks clk]
set_fix_hold                   [get_clocks clk]
set_clock_uncertainty  0.1     [get_clocks clk]
set_clock_latency      0.5     [get_clocks clk]
set_input_transition   0.5     [all_inputs]
set_clock_transition   0.1     [all_clocks]
set_ideal_network              [get_ports clk]

set_input_delay  $t_in  -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay $t_out -clock clk [all_outputs]
 
set_load   0.5    [all_outputs]    
                       