// 151 required glyphs. Keep direct numeric codes 0..31 unchanged.
// Explicit 2048 + 512 row banks avoid padding the whole font to 4096 rows.
module dashboard_compact_font(input wire clk,input wire [11:0] address,
 output wire [15:0] data);
 (* syn_romstyle="block_rom" *) reg [15:0] low[0:2047];
 (* syn_romstyle="block_rom" *) reg [15:0] high[0:511];
 initial begin
  $readmemh("assets/status_font_compact_low.hex",low);
  $readmemh("assets/status_font_compact_high.hex",high);
 end
 reg [15:0] low_q,high_q;reg bank_q;
 always @(posedge clk)begin
  low_q<=low[address[10:0]];high_q<=high[address[8:0]];bank_q<=address[11];
 end
 assign data=bank_q?high_q:low_q;
endmodule
