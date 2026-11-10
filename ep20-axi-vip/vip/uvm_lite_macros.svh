// uvm_lite_macros.svh -- the four UVM macros the VIP uses, for uvm_lite.sv.
// Same names and arguments as UVM's; much less behind them.
`ifndef UVM_LITE_MACROS_SVH
`define UVM_LITE_MACROS_SVH

// registers a component with the factory: type_id, get_type(), get_type_name()
`define uvm_component_utils(T) \
  typedef uvm_lite_pkg::uvm_component_registry #(T, `"T`") type_id; \
  static function uvm_lite_pkg::uvm_object_wrapper get_type(); return type_id::get(); endfunction \
  virtual function string get_type_name(); return `"T`"; endfunction

`define uvm_object_utils(T) \
  typedef uvm_lite_pkg::uvm_object_registry #(T, `"T`") type_id; \
  static function uvm_lite_pkg::uvm_object_wrapper get_type(); return type_id::get(); endfunction \
  virtual function string get_type_name(); return `"T`"; endfunction

`define uvm_error(ID, MSG) begin uvm_lite_pkg::uvm_report_error(ID, MSG); end
`define uvm_info(ID, MSG, VERB) begin uvm_lite_pkg::uvm_report_info(ID, MSG, uvm_lite_pkg::VERB); end
`define uvm_fatal(ID, MSG) begin uvm_lite_pkg::uvm_report_error(ID, MSG); $finish; end

`endif
