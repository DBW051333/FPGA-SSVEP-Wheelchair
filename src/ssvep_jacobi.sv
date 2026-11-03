// Dedicated 4x4, twelve-sweep Jacobi tensor hardware.
// Matrix registers and p/q/row/sweep counters are algorithm-specific state.
module ssvep_jacobi(input wire clk,rst_n,start,with_vectors,
 output logic done,fault,
 output logic [7:0] tensor_a,tensor_b,output logic tensor_wea,tensor_web,
 output logic signed [63:0] tensor_da,tensor_db,input wire signed [63:0] tensor_qa,tensor_qb,
 output logic math_request,output logic [1:0] math_kind,
 output logic signed [63:0] math_a,math_b,
 input wire math_response,math_error,input wire signed [63:0] math_value);
 logic signed [63:0] diag_p,diag_q;logic [3:0] matrix_index;
 logic keep_vectors,rot_vectors;
 logic [1:0] p,q,row;
 logic [3:0] sweep;
 logic [2:0] rot_issue,rot_received;
 logic signed [63:0] apq,negated,magnitude,delta,twice,negative_delta,negative_twice;
 logic signed [63:0] scale_d,scale_a,scale,nd,na,dsq,asq,norm,tangent,t_sq,cosine,sine,shift;
 logic signed [63:0] ax,ay,new_x,new_y,rot_product[0:3];
 logic signed [63:0] add_a,add_b;logic add_sub;
 wire signed [64:0] add_result=add_sub?({add_a[63],add_a}-{add_b[63],add_b}):({add_a[63],add_a}+{add_b[63],add_b});
localparam integer HARDWARE_STATES=85;
typedef enum logic [15:0] {H0,H1,H2,H3,H4,H5,H6,H7,H8,H9,H10,H11,H12,H13,H14,H15,H16,H17,H18,H19,H20,H21,H22,H23,H24,H25,H26,H27,H28,H29,H30,H31,H32,H33,H34,H35,H36,H37,H38,H39,H40,H41,H42,H43,H44,H45,H46,H47,H48,H49,H50,H51,H52,H53,H54,H55,H56,H57,H58,H59,H60,H61,H62,H63,H64,H65,H66,H67,H68,H69,H70,H71,H72,H73,H74,H75,H76,H77,H78,H79,H80,H81,H82,H83,H84} state_t;
state_t state;
always_comb begin
math_request=0;math_kind=0;math_a=0;math_b=0;add_a=0;add_b=0;add_sub=0;tensor_a=0;tensor_b=0;tensor_wea=0;tensor_web=0;tensor_da=0;tensor_db=0;
case(state)
H3:begin tensor_a=8'h70+{4'd0,matrix_index};tensor_wea=1;tensor_da=matrix_index[3:2]==matrix_index[1:0]?64'sd268435456:64'sd0; end
H6:begin tensor_a=8'h60+{4'd0,p,q};tensor_b=8'd0; end
H8:begin add_a=64'sd0;add_b=apq;add_sub=1; end
H11:begin tensor_a=8'h60+{4'd0,p,p};tensor_b=8'h60+{4'd0,q,q}; end
H13:begin add_a=diag_q;add_b=diag_p;add_sub=1; end
H14:begin math_request=1;math_kind=2'd0;math_a=apq;math_b=64'sd536870912; end
H16:begin add_a=64'sd0;add_b=delta;add_sub=1; end
H17:begin add_a=64'sd0;add_b=twice;add_sub=1; end
H20:begin math_request=1;math_kind=2'd1;math_a=delta;math_b=scale; end
H22:begin math_request=1;math_kind=2'd1;math_a=twice;math_b=scale; end
H24:begin math_request=1;math_kind=2'd0;math_a=nd;math_b=nd; end
H26:begin math_request=1;math_kind=2'd0;math_a=na;math_b=na; end
H28:begin add_a=dsq;add_b=asq;add_sub=0; end
H29:begin math_request=1;math_kind=2'd2;math_a=norm;math_b=64'sd0; end
H32:begin add_a=64'sd0;add_b=norm;add_sub=1; end
H33:begin add_a=norm;add_b=nd;add_sub=0; end
H34:begin math_request=1;math_kind=2'd1;math_a=na;math_b=norm; end
H36:begin math_request=1;math_kind=2'd0;math_a=tangent;math_b=tangent; end
H38:begin add_a=t_sq;add_b=64'sd268435456;add_sub=0; end
H39:begin math_request=1;math_kind=2'd2;math_a=t_sq;math_b=64'sd0; end
H41:begin math_request=1;math_kind=2'd1;math_a=64'sd268435456;math_b=norm; end
H43:begin math_request=1;math_kind=2'd0;math_a=tangent;math_b=cosine; end
H45:begin math_request=1;math_kind=2'd0;math_a=tangent;math_b=apq; end
H47:begin add_a=diag_p;add_b=shift;add_sub=1; end
H48:begin add_a=diag_q;add_b=shift;add_sub=0; end
H49:begin tensor_a=8'h60+{4'd0,p,p};tensor_wea=1;tensor_da=diag_p;tensor_b=8'h60+{4'd0,q,q};tensor_web=1'b1;tensor_db=diag_q; end
H50:begin tensor_a=8'h60+{4'd0,p,q};tensor_wea=1;tensor_da=64'd0;tensor_b=8'h60+{4'd0,q,p};tensor_web=1'b1;tensor_db=64'd0; end
H53:begin tensor_a=(rot_vectors?8'h70:8'h60)+{4'd0,row,p};tensor_b=(rot_vectors?8'h70:8'h60)+{4'd0,row,q}; end
H56:begin math_request=1;math_kind=0;math_a=(rot_issue==0||rot_issue==3)?cosine:sine;math_b=(rot_issue==0||rot_issue==2)?ax:ay; end
H58:begin add_a=rot_product[0];add_b=rot_product[1];add_sub=1; end
H59:begin add_a=rot_product[2];add_b=rot_product[3];add_sub=0; end
H60:begin tensor_a=(rot_vectors?8'h70:8'h60)+{4'd0,row,p};tensor_wea=1;tensor_da=new_x;tensor_b=(rot_vectors?8'h70:8'h60)+{4'd0,row,q};tensor_web=1'b1;tensor_db=new_y; end
H62:begin tensor_a=8'h60+{4'd0,p,row};tensor_wea=1;tensor_da=new_x;tensor_b=8'h60+{4'd0,q,row};tensor_web=1'b1;tensor_db=new_y; end
H74:begin tensor_a=8'h60+{4'd0,p,q};tensor_b=8'd0; end
H76:begin add_a=64'sd0;add_b=apq;add_sub=1; end
default:;
endcase
end
always_ff @(posedge clk)begin
if(!rst_n)begin state<=H0;
done<=0;fault<=0;keep_vectors<=0;rot_vectors<=0;p<=0;q<=1;row<=0;sweep<=0;rot_issue<=0;rot_received<=0;
end else begin
done<=0;
case(state)
H0:begin 
if(start)state<=H1; end
H1:begin keep_vectors<=with_vectors;fault<=0;sweep<=0;p<=0;q<=1;matrix_index<=0;
state<=H2; end
H2:begin 
if(!keep_vectors)state<=H6;else state<=H3; end
H3:begin 
state<=H4; end
H4:begin 
if(matrix_index==15)state<=H6;else state<=H5; end
H5:begin matrix_index<=matrix_index+1'b1;
state<=H3; end
H6:begin 
state<=H7; end
H7:begin apq<=tensor_qa;
state<=H8; end
H8:begin negated<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H9; end
H9:begin magnitude<=apq>negated?apq:negated;
state<=H10; end
H10:begin 
if(magnitude<64'sd1)state<=H67;else state<=H11; end
H11:begin 
state<=H12; end
H12:begin diag_p<=tensor_qa;diag_q<=tensor_qb;
state<=H13; end
H13:begin delta<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H14; end
H14:begin 
state<=H15; end
H15:begin if(math_response)begin twice<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H16;end end
H16:begin negative_delta<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H17; end
H17:begin negative_twice<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H18; end
H18:begin scale_d<=delta>negative_delta?delta:negative_delta;scale_a<=twice>negative_twice?twice:negative_twice;
state<=H19; end
H19:begin scale<=scale_d>scale_a?scale_d:scale_a;
state<=H20; end
H20:begin 
state<=H21; end
H21:begin if(math_response)begin nd<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H22;end end
H22:begin 
state<=H23; end
H23:begin if(math_response)begin na<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H24;end end
H24:begin 
state<=H25; end
H25:begin if(math_response)begin dsq<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H26;end end
H26:begin 
state<=H27; end
H27:begin if(math_response)begin asq<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H28;end end
H28:begin norm<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H29; end
H29:begin 
state<=H30; end
H30:begin if(math_response)begin norm<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H31;end end
H31:begin 
if(nd>=0)state<=H33;else state<=H32; end
H32:begin norm<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H33; end
H33:begin norm<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H34; end
H34:begin 
state<=H35; end
H35:begin if(math_response)begin tangent<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H36;end end
H36:begin 
state<=H37; end
H37:begin if(math_response)begin t_sq<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H38;end end
H38:begin t_sq<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H39; end
H39:begin 
state<=H40; end
H40:begin if(math_response)begin norm<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H41;end end
H41:begin 
state<=H42; end
H42:begin if(math_response)begin cosine<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H43;end end
H43:begin 
state<=H44; end
H44:begin if(math_response)begin sine<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H45;end end
H45:begin 
state<=H46; end
H46:begin if(math_response)begin shift<=math_value;end
if(math_response)begin if(math_error)state<=H84;else state<=H47;end end
H47:begin diag_p<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H48; end
H48:begin diag_q<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H49; end
H49:begin 
state<=H50; end
H50:begin 
state<=H51; end
H51:begin row<=0;rot_vectors<=0;
state<=H52; end
H52:begin 
if(!rot_vectors&&(row==p||row==q))state<=H63;else state<=H53; end
H53:begin 
state<=H54; end
H54:begin ax<=tensor_qa;ay<=tensor_qb;
state<=H55; end
H55:begin rot_issue<=0;rot_received<=0;
state<=H56; end
H56:begin rot_issue<=rot_issue+1'b1;
if(rot_issue==3)state<=H57;else state<=H56; end
H57:begin if(math_response)begin rot_product[rot_received]<=math_value;rot_received<=rot_received+1'b1;end
if(math_response)begin if(math_error)state<=H84;else if(rot_received==3)state<=H58;end end
H58:begin new_x<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H59; end
H59:begin new_y<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H60; end
H60:begin 
state<=H61; end
H61:begin 
if(rot_vectors)state<=H63;else state<=H62; end
H62:begin 
state<=H63; end
H63:begin 
if(row==3)state<=H65;else state<=H64; end
H64:begin row<=row+1'b1;
state<=H52; end
H65:begin 
if(rot_vectors||!keep_vectors)state<=H67;else state<=H66; end
H66:begin row<=0;rot_vectors<=1;
state<=H52; end
H67:begin 
if(q==3)state<=H69;else state<=H68; end
H68:begin q<=q+1'b1;
state<=H6; end
H69:begin 
if(p==2)state<=H71;else state<=H70; end
H70:begin p<=p+1'b1;q<=p+2'd2;
state<=H6; end
H71:begin 
if(sweep==11)state<=H73;else state<=H72; end
H72:begin sweep<=sweep+1'b1;p<=0;q<=1;
state<=H6; end
H73:begin p<=0;q<=1;
state<=H74; end
H74:begin 
state<=H75; end
H75:begin apq<=tensor_qa;
state<=H76; end
H76:begin negated<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H84;else state<=H77; end
H77:begin magnitude<=apq>negated?apq:negated;
state<=H78; end
H78:begin 
if(magnitude>64'sd134)state<=H84;else state<=H79; end
H79:begin 
if(q==3)state<=H81;else state<=H80; end
H80:begin q<=q+1'b1;
state<=H74; end
H81:begin 
if(p==2)state<=H83;else state<=H82; end
H82:begin p<=p+1'b1;q<=p+2'd2;
state<=H74; end
H83:begin done<=1;
state<=H0; end
H84:begin fault<=1;done<=1;
state<=H0; end
default:state<=H84;
endcase
end
end
endmodule
