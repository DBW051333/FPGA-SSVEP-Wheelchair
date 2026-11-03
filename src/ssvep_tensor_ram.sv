// Dedicated 4x4 tensor banks: Cxx,Cxy,Wx,Wy,T,M,J,V. Four physical DPBs.
// The two ports support two reads, a read/write, or two distinct writes/clock.
module ssvep_tensor_ram(input wire clk,wea,web,input wire [7:0] aa,ab,
 input wire [63:0] da,db,output wire [63:0] qa,qb);
 genvar k;
 generate for(k=0;k<4;k=k+1)begin:bit_slices
  DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b01),
        .WRITE_MODE1(2'b01),.BIT_WIDTH_0(16),.BIT_WIDTH_1(16)) memory(
   .CLKA(clk),.CEA(1'b1),.OCEA(1'b1),.RESETA(1'b0),.WREA(wea),
   .ADA({2'b0,aa,4'b0011}),.DIA(da[k*16+:16]),.DOA(qa[k*16+:16]),.BLKSELA(3'd0),
   .CLKB(clk),.CEB(1'b1),.OCEB(1'b1),.RESETB(1'b0),.WREB(web),
   .ADB({2'b0,ab,4'b0011}),.DIB(db[k*16+:16]),.DOB(qb[k*16+:16]),.BLKSELB(3'd0));
 end endgenerate
 `ifdef SIM
 always @(posedge clk)if(wea&&web&&aa==ab)$fatal(1,"Conflicting tensor RAM writes");
 `endif
endmodule
