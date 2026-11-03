// Cyton+Daisy serial format, 115200 8N1 after receiver USB bridge.
// BrainFlow CytonDaisy commits Cyton rows on every valid odd packet.
// No adjacent even packet is required for the four Cyton attention channels.
// Select Cyton ch1..4, gain=24, Vref=4.5V, matching the supplied configuration.
// No electrical connection to a particular receiver is assumed by this RTL.
module attention_cyton_rx # (parameter integer CLOCK_HZ=50000000)(
    input logic clk,rst_n,byte_valid,byte_error,
    input logic [7:0] byte_data,
    output logic sample_valid,
    input logic sample_ready,
    output logic signed [31:0] sample0,sample1,sample2,sample3,
    output logic [15:0] sample_sequence,
    output logic overrun,
    output logic [31:0] malformed_packets,
    output logic [15:0] gap_over_5ms,gap_over_50ms,
    output logic [7:0] timeout_errors,footer_errors
);
    logic [5:0] pos;
    logic [7:0] packet_id,last_odd_id;
    logic [23:0] assembled[0:3];
    logic have_pair;
    logic [31:0] timer;
    wire [7:0] pair_delta=packet_id-last_odd_id;
    function automatic signed [31:0] to_uv_q8(input logic [23:0] raw);
        logic signed [55:0] product;
        begin
            // round(187500 / (2^23-1) * 256 * 2^24) = 96000011.
            product=$signed(raw)*56'sd96000011;
            to_uv_q8=32'((product+56'sd8388608)>>>24);
        end
    endfunction
    always_ff @(posedge clk)begin
        if(!rst_n)begin
            pos<=0;packet_id<=0;last_odd_id<=0;have_pair<=0;
            timer<=0;sample_valid<=0;sample_sequence<=0;overrun<=0;malformed_packets<=0;gap_over_5ms<=0;
            gap_over_50ms<=0;timeout_errors<=0;footer_errors<=0;
            sample0<=0;sample1<=0;sample2<=0;sample3<=0;
            for(integer i=0;i<4;i=i+1)assembled[i]<=0;
        end else begin
            sample_valid<=0;overrun<=0;
            if(sample_valid&&!sample_ready)overrun<=1;
            if(pos!=0&&timer<CLOCK_HZ/2)timer<=timer+1'b1;
            // Observe the old deadline without discarding a fragmented frame.
            if(pos!=0&&timer==CLOCK_HZ/200)gap_over_5ms<=gap_over_5ms+1'b1;
            if(pos!=0&&timer==CLOCK_HZ/20)gap_over_50ms<=gap_over_50ms+1'b1;
            if(byte_error || (pos!=0&&timer>=CLOCK_HZ/2))begin
                if(!byte_error)timeout_errors<=timeout_errors+1'b1;
                pos<=0;timer<=0;malformed_packets<=malformed_packets+1'b1;
            end else if(byte_valid)begin
                timer<=0;
                if(pos==0)begin if(byte_data==8'ha0)pos<=1;end
                else if(pos==1)begin packet_id<=byte_data;pos<=2;end
                else if(pos<32)begin
                    if(pos>=2&&pos<=13)begin
                        case(pos)
                        2,3,4:assembled[0]<={assembled[0][15:0],byte_data};
                        5,6,7:assembled[1]<={assembled[1][15:0],byte_data};
                        8,9,10:assembled[2]<={assembled[2][15:0],byte_data};
                        11,12,13:assembled[3]<={assembled[3][15:0],byte_data};
                        default:;
                        endcase
                    end
                    pos<=pos+1'b1;
                end else begin
                    pos<=0;
                    if(byte_data<8'hc0||byte_data>8'hc6)begin
                        footer_errors<=footer_errors+1'b1;
                        malformed_packets<=malformed_packets+1'b1;
                        if(byte_data==8'ha0)pos<=1;
                    end else begin
                        if(packet_id[0])begin
                                sample0<=to_uv_q8(assembled[0]);sample1<=to_uv_q8(assembled[1]);
                                sample2<=to_uv_q8(assembled[2]);sample3<=to_uv_q8(assembled[3]);
                                sample_sequence<=have_pair ? sample_sequence+{9'd0,pair_delta[7:1]} : 16'd0;
                                last_odd_id<=packet_id;have_pair<=1;sample_valid<=1;
                        end
                    end
                end
            end
        end
    end
endmodule
