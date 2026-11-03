// Explicit three-page state machine. Consume each result edge at most once.
module page_command_router #(parameter AUTO_MODE=0,CONTINUOUS_MODE=0)(input wire clk,rst_n,start_press,stop_press,next_press,prev_press,
 input wire result_valid,input wire [2:0] result_code,
 output reg [1:0] page,session_page,output wire cancel,
 output wire direction_valid,output wire [2:0] direction_code,
 output wire panel_valid,output wire [2:0] panel_code);
 localparam [2:0] DIRECTIONS=3'b001,FUNCTIONS=3'b010,SPEED_SOS=3'b100;
 (* syn_encoding="onehot",syn_preserve=1 *) reg [2:0] page_state;
 // S3 advances one page in both automatic and manual operation.
 // S2 remains reserved for the independent power key in automatic operation.
 wire manual_next=next_press;
 wire manual_prev=!AUTO_MODE&&prev_press;
 reg armed,result_previous;
 always @*begin
  case(page_state)DIRECTIONS:page=2'd0;FUNCTIONS:page=2'd1;SPEED_SOS:page=2'd2;default:page=2'd0;endcase
 end
 wire accepted=armed&&result_valid&&!result_previous&&page==session_page&&
               !start_press&&!stop_press&&!manual_next&&!manual_prev;
 wire gaze_page=accepted&&((session_page==0&&result_code==5)||
                           ((session_page==1||session_page==2)&&result_code==4));
 assign cancel=manual_next||manual_prev||gaze_page;
 wire valid=accepted&&!cancel&&result_code>=1&&result_code<=4;
 assign direction_valid=valid&&session_page==0;
 assign direction_code=result_code;
 assign panel_valid=valid&&(session_page==1||session_page==2)&&result_code<=3;
 assign panel_code=session_page==1?(result_code==3?3'd5:result_code):
                   result_code==1?3'd3:result_code==2?3'd4:3'd6;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin page_state<=DIRECTIONS;session_page<=0;armed<=0;result_previous<=0;end
  else begin
   result_previous<=result_valid;
   if(result_valid&&!CONTINUOUS_MODE)armed<=0;
   if(start_press)begin session_page<=page;armed<=1;end
   if(stop_press||(!CONTINUOUS_MODE&&cancel))armed<=0;
   if(manual_next||gaze_page)begin
    case(page_state)
     DIRECTIONS:begin page_state<=FUNCTIONS;session_page<=1;end
     FUNCTIONS:begin page_state<=SPEED_SOS;session_page<=2;end
     default:begin page_state<=DIRECTIONS;session_page<=0;end
    endcase
   end else if(manual_prev)begin
    case(page_state)
     DIRECTIONS:begin page_state<=SPEED_SOS;session_page<=2;end
     FUNCTIONS:begin page_state<=DIRECTIONS;session_page<=0;end
     default:begin page_state<=FUNCTIONS;session_page<=1;end
    endcase
   end else if(page_state!=DIRECTIONS&&page_state!=FUNCTIONS&&page_state!=SPEED_SOS)begin
    page_state<=DIRECTIONS;session_page<=0;armed<=0;
   end
  end
endmodule
