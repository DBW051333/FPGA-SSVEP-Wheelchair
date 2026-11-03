module uart_rx # (parameter integer CLOCK_HZ=50000000,BAUD=115200)(
    input logic clk,rst_n,rx,
    output logic valid,error,
    output logic [7:0] data
);
    localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
    logic rx1,rx2;
    logic [2:0] state,bit_index;
    localparam integer TIMER_BITS=DIV>1 ? $clog2(DIV):1;
    logic [TIMER_BITS-1:0] timer;
    logic [7:0] shift;
    always_ff @(posedge clk)begin
        if(!rst_n)begin rx1<=1;rx2<=1;state<=0;timer<=0;bit_index<=0;shift<=0;valid<=0;error<=0;data<=0;end
        else begin
            rx1<=rx;rx2<=rx1;valid<=0;error<=0;
            case(state)
            0:if(!rx2)begin timer<=DIV/2-1;state<=1;end
            1:if(timer!=0)timer<=timer-1'b1;else if(rx2)state<=0;
              else begin timer<=DIV-1;bit_index<=0;state<=2;end
            2:if(timer!=0)timer<=timer-1'b1;else begin
                shift[bit_index]<=rx2;timer<=DIV-1;
                if(bit_index==7)state<=3;else bit_index<=bit_index+1'b1;
            end
            3:if(timer!=0)timer<=timer-1'b1;else begin
                if(rx2)begin valid<=1;data<=shift;end else error<=1;
                state<=0;
            end
            default:state<=0;
            endcase
        end
    end
endmodule

module uart_tx # (parameter integer CLOCK_HZ=50000000,BAUD=115200)(
    input logic clk,rst_n,valid,
    input logic [7:0] data,
    output wire ready,
    output wire tx
);
    localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
    logic [9:0] shift;
    logic [3:0] bits_left;
    localparam integer TIMER_BITS=DIV>1 ? $clog2(DIV):1;
    logic [TIMER_BITS-1:0] timer;
    assign ready=bits_left==0;
    assign tx=bits_left==0 ? 1'b1 : shift[0];
    always_ff @(posedge clk)begin
        if(!rst_n)begin shift<=10'h3ff;bits_left<=0;timer<=0;end
        else if(ready)begin if(valid)begin shift<={1'b1,data,1'b0};bits_left<=10;timer<=DIV-1;end end
        else if(timer!=0)timer<=timer-1'b1;
        else begin timer<=DIV-1;shift<={1'b1,shift[9:1]};bits_left<=bits_left-1'b1;end
    end
endmodule
