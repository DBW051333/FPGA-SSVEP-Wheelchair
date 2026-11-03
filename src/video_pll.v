module Gowin_PLL(output lock,output clkout0,output clkout1,input clkin,input reset,input mdclk);
 plla_clock #(.FCLK_IN("27"),.IDIV(1),.MDIV(27),.MFRAC(4),.ODIV0(10),.ODIV1(2),.OUT0("FALSE"),.OUT1("TRUE"))
 core(clkin,reset,mdclk,clkout0,clkout1,lock);
endmodule
