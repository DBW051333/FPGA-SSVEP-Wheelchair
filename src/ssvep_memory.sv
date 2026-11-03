// Two-second profile uses 4K + 2K banks; legacy 8K + 2K remains supported.
// Both banks use true dual ports; bank selection is registered with RAM reads.
module ssvep_data_ram #(
    parameter integer DEPTH=6144, COMPACT_BAD=0,
    parameter INIT_FILE="assets/data.hex",
    parameter LOW_FILE="assets/data_low.hex",HIGH_FILE="assets/data_high.hex"
)(
    input wire clk,write_enable,
    input wire [13:0] read_address,write_address,read_address_b,
    input wire signed [63:0] write_data,
    output wire signed [63:0] read_data,read_data_b
);
    wire [13:0] port_a_address=write_enable ? write_address : read_address;
    generate if(COMPACT_BAD && DEPTH==6144)begin:typed_storage
        ssvep_typed_state_ram memory(clk,write_enable,port_a_address,read_address_b,write_data,read_data,read_data_b);
    end else if(DEPTH==6144 || DEPTH==10240)begin:banked
        localparam integer BANK_BIT=DEPTH==6144 ? 12:13;
        localparam integer LOW_DEPTH=1<<BANK_BIT;
        wire signed [63:0] low_a,low_b,high_a,high_b;
        logic select_a,select_b;
        always_ff @(posedge clk)begin
            select_a<=port_a_address[BANK_BIT];select_b<=read_address_b[BANK_BIT];
        end
        ssvep_data_bank #(.DEPTH(LOW_DEPTH),.AW(BANK_BIT),.INIT_FILE(LOW_FILE)) low_bank(
            clk,write_enable&&!port_a_address[BANK_BIT],port_a_address[BANK_BIT-1:0],read_address_b[BANK_BIT-1:0],write_data,low_a,low_b);
        ssvep_data_bank #(.DEPTH(2048),.AW(11),.INIT_FILE(HIGH_FILE)) high_bank(
            clk,write_enable&&port_a_address[BANK_BIT]&&(port_a_address<DEPTH),port_a_address[10:0],read_address_b[10:0],write_data,high_a,high_b);
        assign read_data=select_a ? high_a:low_a;
        assign read_data_b=select_b ? high_b:low_b;
    end else begin:linear
        ssvep_data_bank #(.DEPTH(DEPTH),.AW(14),.INIT_FILE(INIT_FILE)) memory_bank(
            clk,write_enable,port_a_address,read_address_b,write_data,read_data,read_data_b);
    end endgenerate
endmodule

module ssvep_data_bank #(
    parameter integer DEPTH=8192,AW=13,
    parameter INIT_FILE="assets/data_low.hex"
)(
    input wire clk,write_enable,
    input wire [AW-1:0] address_a,address_b,
    input wire signed [63:0] write_data,
    output logic signed [63:0] read_a,read_b
);
    (* syn_ramstyle="block_ram" *) logic [63:0] memory[0:DEPTH-1];
    initial $readmemh(INIT_FILE,memory);
    // A shared A-port address and explicit write-through mode are required
    // for Gowin DPB inference. Read data during a write is not consumed.
    always_ff @(posedge clk)begin
        if(write_enable)begin memory[address_a]<=write_data;read_a<=write_data;end
        else read_a<=memory[address_a];
    end
    always_ff @(posedge clk)read_b<=memory[address_b];
endmodule



// Dedicated dual-read reference store gives periodic dot products four reads
// per clock together with the two EEG RAM ports. Resource sharing is secondary.
module ssvep_reference_rom #(parameter INIT_FILE="assets/reference.hex")(
 input wire clk,input wire [11:0] address_a,address_b,
 output wire signed [63:0] data_a,data_b);
 generate if(INIT_FILE=="assets/reference.hex")begin:packed_banks
 wire [31:0] qa[0:2],qb[0:2];
 reg [1:0] sa,sb;
 always @(posedge clk)begin sa<=address_a[11:10];sb<=address_b[11:10];end
 `include "reference_dpb_init.vh"
 wire signed [31:0] a32=sa<3?qa[sa]:32'bx;
 wire signed [31:0] b32=sb<3?qb[sb]:32'bx;
 assign data_a=a32;assign data_b=b32;
 end else begin:generic
 ssvep_reference_rom_generic #(.INIT_FILE(INIT_FILE)) fallback(clk,address_a,address_b,data_a,data_b);
 end endgenerate
endmodule

module ssvep_reference_rom_generic #(
    parameter INIT_FILE="assets/reference.hex"
)(
    input wire clk,
    input wire [11:0] address_a,address_b,
    output logic signed [63:0] data_a,data_b
);
    (* syn_romstyle="block_rom" *) logic signed [31:0] memory[0:3071];
    initial $readmemh(INIT_FILE,memory);
    always_ff @(posedge clk)begin data_a<=memory[address_a];data_b<=memory[address_b];end
endmodule


// Logical addresses remain unchanged; numeric data never stores flag padding.
// This contract is generated/checked by tools/generate_compact_state.py.
module ssvep_typed_state_ram(
 input wire clk,we,input wire [13:0] aa,ab,input wire signed [63:0] data,
 output wire signed [63:0] qa,qb);
 localparam integer FIRST=1799, LAST=3299;
 wire fa=aa>=FIRST&&aa<LAST,fb=ab>=FIRST&&ab<LAST;
 wire [12:0] na=aa>=LAST?13'(aa-1500):aa[12:0];
 wire [12:0] nb=ab>=LAST?13'(ab-1500):ab[12:0];
 wire [10:0] ia=11'(aa-FIRST),ib=11'(ab-FIRST);
 (* syn_ramstyle="block_ram" *) reg flags[0:1499];
 initial $readmemh("assets/compact_bad.hex",flags);
 reg fqa,fqb,sfa,sfb,sha,shb;
 wire signed [63:0] la,lb,ha,hb;
 always @(posedge clk)begin
  sfa<=fa;sfb<=fb;sha<=na[12];shb<=nb[12];
  if(we&&fa)begin flags[ia]<=data[0];fqa<=data[0];end
  else fqa<=flags[ia];
 end
 always @(posedge clk)fqb<=flags[ib];
 ssvep_data_bank #(.DEPTH(4096),.AW(12),.INIT_FILE("assets/compact_numeric_low.hex")) low(
  clk,we&&!fa&&!na[12],na[11:0],nb[11:0],data,la,lb);
 ssvep_data_bank #(.DEPTH(1024),.AW(10),.INIT_FILE("assets/compact_numeric_high.hex")) high(
  clk,we&&!fa&&na[12],na[9:0],nb[9:0],data,ha,hb);
 assign qa=sfa?{63'd0,fqa}:sha?ha:la;
 assign qb=sfb?{63'd0,fqb}:shb?hb:lb;
 `ifdef SIM
 always @(posedge clk)if(we&&fa&&data[63:1]!=0)$fatal(1,"Non-boolean BAD write violates typed storage contract");
 `endif
endmodule
