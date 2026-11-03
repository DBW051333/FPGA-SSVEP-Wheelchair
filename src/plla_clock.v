// GW5AT-60B PLLA with the vendor's required mDRP startup calibration.
module plla_clock #(parameter FCLK_IN="50",parameter IDIV=1,MDIV=27,
 parameter MFRAC=0,ODIV0=50,ODIV1=2,
 parameter OUT0="TRUE",OUT1="FALSE")
 (input clkin,input reset,input mdclk,output clkout0,output clkout1,output lock);
 wire raw_lock,pll_reset,inc;wire [1:0] opc;wire [7:0] wdi,rdo;
 PLLA #(.FCLKIN(FCLK_IN),.IDIV_SEL(IDIV),.FBDIV_SEL(1),
 .MDIV_SEL(MDIV),.MDIV_FRAC_SEL(MFRAC),.ODIV0_SEL(ODIV0),.ODIV1_SEL(ODIV1),
 .CLKOUT0_EN(OUT0),.CLKOUT1_EN(OUT1),.CLKOUT2_EN("FALSE"),
 .CLKOUT3_EN("FALSE"),.CLKOUT4_EN("FALSE"),.CLKOUT5_EN("FALSE"),.CLKOUT6_EN("FALSE"),
 .CLKFB_SEL("INTERNAL")) PLL_inst(
 .CLKIN(clkin),.CLKFB(1'b0),.RESET(pll_reset),.PLLPWD(1'b0),
 .RESET_I(1'b0),.RESET_O(1'b0),.LOCK(raw_lock),
 .CLKOUT0(clkout0),.CLKOUT1(clkout1),.CLKOUT2(),.CLKOUT3(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKFBOUT(),
 .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),.SSCON(1'b0),
 .SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),
 .MDCLK(mdclk),.MDOPC(opc),.MDAINC(inc),.MDWDI(wdi),.MDRDO(rdo));
 PLL_INIT #(.CLK_PERIOD(20),.MULTI_FAC(MDIV/IDIV)) init(
 .I_RST(reset),.I_MD_CLK(mdclk),.O_RST(pll_reset),.I_LOCK(raw_lock),.O_LOCK(lock),
 .O_MD_INC(inc),.O_MD_OPC(opc),.O_MD_WR_DATA(wdi),.I_MD_RD_DATA(rdo),
 .PLL_INIT_BYPASS(1'b0),.MDRDO(),.MDOPC(2'b0),.MDAINC(1'b0),.MDWDI(8'b0));
endmodule
