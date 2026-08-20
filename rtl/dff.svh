`ifndef DFF_SVH
`define DFF_SVH

// Sequential registers: call these macros instead of always_ff.
// _inst    : unique instance name
// _width   : register width
// _q       : register
// _d       : next value
// _en      : clock enable (DFFE only)
`define DFF(_inst, _width, _q, _d, _clk, _rst_n, _rst_val) dff #(.WIDTH(_width), .RST_VAL(_rst_val)) _inst (.clk(_clk), .rst_n(_rst_n), .d(_d), .q(_q));
`define DFFE(_inst, _width, _q, _d, _en, _clk, _rst_n, _rst_val) dffe #(.WIDTH(_width), .RST_VAL(_rst_val)) _inst (.clk(_clk), .rst_n(_rst_n), .en(_en), .d(_d), .q(_q));

`endif
