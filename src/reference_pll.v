module Reference_PLL(output lock,output clkout0,output clkout1,input clkin,input reset,input mdclk);
 plla_clock #(.FCLK_IN("50"),.IDIV(1),.MDIV(27),.ODIV0(50),.OUT0("TRUE"),.OUT1("FALSE"))
 core(clkin,reset,mdclk,clkout0,clkout1,lock);
endmodule
