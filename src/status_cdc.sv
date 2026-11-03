// Atomic mailbox. Payload stays fixed until the receiver acknowledges it.
// Destination commits only at vertical blank; no per-bit multi-bit synchronizer.
module status_cdc #(parameter WIDTH=24)(
 input wire src_clk,src_rst_n,input wire [WIDTH-1:0] src_data,
 input wire dst_clk,dst_rst_n,frame_tick,output reg [WIDTH-1:0] dst_data);
 reg [WIDTH-1:0] mailbox,pending;reg request,acknowledge,received;
 (* syn_preserve=1 *) reg [1:0] ack_sync,req_sync;
 always @(posedge src_clk or negedge src_rst_n)
  if(!src_rst_n)begin mailbox<=0;request<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],acknowledge};
   if(request==ack_sync[1]&&mailbox!=src_data)begin mailbox<=src_data;request<=!request;end
  end
 always @(posedge dst_clk or negedge dst_rst_n)
  if(!dst_rst_n)begin req_sync<=0;acknowledge<=0;received<=0;pending<=0;dst_data<=0;end
  else begin
   req_sync<={req_sync[0],request};
   if(req_sync[1]!=received)begin
    pending<=mailbox;received<=req_sync[1];acknowledge<=req_sync[1];
   end
   if(frame_tick)dst_data<=pending;
  end
endmodule
