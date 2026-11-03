// Shared signed Q35.28 arithmetic. All operations are bounded, synthesizable.
// op: 0 fixed multiply, 1 fixed divide, 2 fixed sqrt, 3 full 128-bit multiply,
//     4 signed 128/64 divide (dot-product averaging).
module qmath #(parameter integer ENABLE_MULTIPLY=1, FAST_DIVIDE=0, RADIX4_DIVIDE=0) (
    input logic clk, rst_n, start,
    input logic [2:0] op,
    input logic signed [63:0] a, b,
    input logic signed [127:0] wide_a,
    output logic busy, done, error,
    output logic signed [63:0] result,
    output logic signed [127:0] product
);
    localparam integer F = 28;
    typedef enum logic [3:0] {IDLE, MPART, MSUM, MOUT, DIV_LENGTH,DIV_SHIFT,DIVIDE,DIV_RESULT,ROOT_LENGTH,ROOT_SHIFT,ROOT} state_t;
    state_t state;
    logic [2:0] operation;
    logic negative;
    logic [63:0] aa, bb;
    logic [127:0] magnitude, numerator, quotient;
    logic [64:0] remainder;
    logic [63:0] denominator;
    logic [7:0] count;
    logic [6:0] normalization_shift;
    // One 32x32 partial product per clock replaces four parallel multipliers.
    // Scalar multiplication is handshake based, so four extra cycles do not
    // alter its numerical contract or the independent streaming pipeline.
    wire [63:0] partial_product;
    generate if(ENABLE_MULTIPLY) begin:scalar_multiplier
      assign partial_product=(count[0]?aa[63:32]:aa[31:0])*(count[1]?bb[63:32]:bb[31:0]);
    end else begin:no_scalar_multiplier
      assign partial_product=64'd0;
    end endgenerate
    // Seven balanced selection levels encode the meaningful numerator bits.
    // Encoding and shifting use separate clocks from the iterative datapath.
    wire [127:0] length_input=numerator;
    wire l64=|length_input[127:64];
    wire [63:0] lvalue64=l64 ? length_input[127:64]:length_input[63:0];
    wire l32=|lvalue64[63:32];wire [31:0] lvalue32=l32 ? lvalue64[63:32]:lvalue64[31:0];
    wire l16=|lvalue32[31:16];wire [15:0] lvalue16=l16 ? lvalue32[31:16]:lvalue32[15:0];
    wire l8=|lvalue16[15:8];wire [7:0] lvalue8=l8 ? lvalue16[15:8]:lvalue16[7:0];
    wire l4=|lvalue8[7:4];wire [3:0] lvalue4=l4 ? lvalue8[7:4]:lvalue8[3:0];
    wire l2=|lvalue4[3:2];wire [1:0] lvalue2=l2 ? lvalue4[3:2]:lvalue4[1:0];
    wire [7:0] used_bits=length_input==0 ? 8'd0 : {1'b0,l64,l32,l16,l8,l4,l2,lvalue2[1]}+8'd1;
    wire [7:0] used_pairs=(used_bits+8'd1)>>1;
    // Quotient-length normalization skips leading zero quotient bits exactly.
    wire d32=|denominator[63:32];
    wire [31:0] dv32=d32?denominator[63:32]:denominator[31:0];
    wire d16=|dv32[31:16];wire [15:0] dv16=d16?dv32[31:16]:dv32[15:0];
    wire d8=|dv16[15:8];wire [7:0] dv8=d8?dv16[15:8]:dv16[7:0];
    wire d4=|dv8[7:4];wire [3:0] dv4=d4?dv8[7:4]:dv8[3:0];
    wire d2=|dv4[3:2];wire [1:0] dv2=d2?dv4[3:2]:dv4[1:0];
    wire [6:0] denominator_bits=denominator==0?7'd0:{1'b0,d32,d16,d8,d4,d2,dv2[1]}+7'd1;
    wire [7:0] quotient_bits=used_bits-{1'b0,denominator_bits}+8'd1;
    wire [192:0] division_shift={65'd0,numerator}<<normalization_shift;
    logic [127:0] radicand;
    // sqrt(abs_a << 28) has at most 46 significant root bits because a is a
    // nonnegative signed 64-bit input. The restoring-root invariant r<=2*q
    // therefore bounds the saved remainder to 46 bits and the trial to 48.
    logic [47:0] root_remainder;
    logic [45:0] root_value;
    wire [63:0] abs_a = a[63] ? (~$unsigned(a)+64'd1) : $unsigned(a);
    wire [63:0] abs_b = b[63] ? (~$unsigned(b)+64'd1) : $unsigned(b);
    wire [127:0] abs_wide = wide_a[127] ? (~$unsigned(wide_a)+128'd1) : $unsigned(wide_a);
    wire [64:0] div_trial = {remainder[63:0],numerator[127]};
    wire div_bit = div_trial >= {1'b0,denominator};
    wire [127:0] next_quotient = {quotient[126:0],div_bit};
    wire [64:0] first_remainder=div_bit?div_trial-{1'b0,denominator}:div_trial;
    wire [64:0] second_trial={first_remainder[63:0],numerator[126]};
    wire second_bit=second_trial>={1'b0,denominator};
    wire [127:0] next_quotient_two={quotient[125:0],div_bit,second_bit};
    wire [47:0] root_trial = {root_remainder[45:0],radicand[127:126]};
    wire [47:0] root_test = {root_value,2'b01};
    wire root_bit = root_trial >= root_test;
    wire [45:0] next_root = {root_value[44:0],root_bit};
    wire [127:0] shifted_magnitude = magnitude >> F;
    // Round to nearest, ties away from zero; overflow always reported.
    wire [127:0] rounded_magnitude = shifted_magnitude + {{127{1'b0}},magnitude[F-1]};
    wire [127:0] signed_product = negative ? (~magnitude + 128'd1) : magnitude;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; busy<=0; done<=0; error<=0;
            result<=0; product<=0; count<=0;normalization_shift<=0;
            aa<=0;bb<=0;negative<=0;operation<=0;
            magnitude<=0;
            numerator<=0;quotient<=0;remainder<=0;denominator<=0;
            radicand<=0;root_remainder<=0;root_value<=0;
        end else begin
            done<=0;
            case(state)
            IDLE: if(start) begin
                busy<=1;error<=0;operation<=op;
                negative<=a[63]^b[63]; aa<=abs_a;bb<=abs_b;
                case(op)
                0,3: if(ENABLE_MULTIPLY)begin count<=0;magnitude<=0;state<=MPART;end
                     else begin error<=1;busy<=0;done<=1;end
                1,4: begin
                    numerator <= op==1 ? ({64'd0,abs_a} << F) : abs_wide;
                    negative <= op==1 ? (a[63]^b[63]) : (wide_a[127]^b[63]);
                    denominator<=abs_b;quotient<=0;remainder<=0;count<=128;
                    if(b==0) begin error<=1;result<=0;busy<=0;done<=1;end
                    else state<=DIV_LENGTH;
                end
                2: begin
                    numerator<=({64'd0,abs_a} << F);
                    radicand<=({64'd0,abs_a} << F);root_remainder<=0;root_value<=0;count<=64;
                    if(a<0) begin error<=1;result<=0;busy<=0;done<=1;end
                    else state<=ROOT_LENGTH;
                end
                default: begin error<=1;busy<=0;done<=1;end
                endcase
            end
            MPART: begin
                // One 32x32 partial product per clock; the four results are
                // aligned and accumulated into the 128-bit magnitude.
                magnitude<=magnitude+({64'd0,partial_product}<<({2'b0,count}<<5));
                if(count==3)state<=MOUT;else begin count<=count+1'b1;end
            end
            MOUT: begin
                product<=$signed(signed_product);
                result<=negative ? -$signed(rounded_magnitude[63:0]) : $signed(rounded_magnitude[63:0]);
                if(operation==0 && (rounded_magnitude > (negative ? 128'h8000000000000000 : 128'h7fffffffffffffff)))
                    error<=1;
                busy<=0;done<=1;state<=IDLE;
            end
            DIV_LENGTH:begin
                if(numerator==0)begin result<=0;busy<=0;done<=1;state<=IDLE;end
                else if(denominator==1)begin
                    // Exact bypass used by 4-element matrix dot products.
                    quotient<=numerator;state<=DIV_RESULT;
                end else if(FAST_DIVIDE&&used_bits<{1'b0,denominator_bits})begin
                    result<=0;busy<=0;done<=1;state<=IDLE;
                end else begin
                    count<=FAST_DIVIDE?quotient_bits:used_bits;
                    normalization_shift<=7'(8'd128-(FAST_DIVIDE?quotient_bits:used_bits));state<=DIV_SHIFT;
                end
            end
            DIV_SHIFT:begin
                if(FAST_DIVIDE)begin remainder<=division_shift[192:128];numerator<=division_shift[127:0];end
                else numerator<=numerator<<normalization_shift;
                state<=DIVIDE;
            end
            ROOT_LENGTH:begin
                if(radicand==0)begin result<=0;busy<=0;done<=1;state<=IDLE;end
                else begin count<=used_pairs;normalization_shift<=7'(8'd128-(used_pairs<<1));state<=ROOT_SHIFT;end
            end
            ROOT_SHIFT:begin radicand<=radicand<<normalization_shift;state<=ROOT;end
            DIVIDE: begin
                if(RADIX4_DIVIDE&&count>=2)begin
                    remainder<=second_bit?second_trial-{1'b0,denominator}:second_trial;
                    numerator<=numerator<<2;quotient<=next_quotient_two;count<=count-8'd2;
                    if(count==2)state<=DIV_RESULT;
                end else begin
                    remainder<=div_bit ? div_trial-{1'b0,denominator} : div_trial;
                    numerator<=numerator<<1;quotient<=next_quotient;count<=count-1'b1;
                    if(count==1)state<=DIV_RESULT;
                end
            end
            DIV_RESULT:begin
                // Separate the long trial comparison from sign restoration.
                result<=negative ? -$signed(quotient[63:0]) : $signed(quotient[63:0]);
                if(quotient>(negative ? 128'h8000000000000000 : 128'h7fffffffffffffff))error<=1;
                busy<=0;done<=1;state<=IDLE;
            end
            ROOT: begin
                root_remainder<=root_bit ? root_trial-root_test : root_trial;
                root_value<=next_root;radicand<=radicand<<2;count<=count-1'b1;
                if(count==1) begin result<=$signed({18'd0,next_root});busy<=0;done<=1;state<=IDLE;end
            end
            default:state<=IDLE;
            endcase
        end
    end
endmodule

// One accepted pair per clock, with exact signed 128-bit products.
// Independent of scalar divide/sqrt: stream work never waits for their handshake.
module ssvep_product_pipe(
    input wire clk,rst_n,valid,
    input wire signed [63:0] a,b,
    output wire out_valid,
    output wire signed [127:0] product,
    output wire signed [63:0] rounded,
    output wire overflow
);
    logic [5:0] pending,negative;
    logic signed [63:0] raw_a,raw_b;
    logic [63:0] aa,bb,p00,p01,p10,p11;
    logic [127:0] lo,hi,magnitude;
    logic signed [127:0] output_product;
    logic signed [63:0] output_rounded;
    logic output_overflow;
    wire [127:0] q=(magnitude>>28)+{127'd0,magnitude[27]};
    assign out_valid=pending[5];
    assign product=output_product;
    assign rounded=output_rounded;
    assign overflow=output_overflow;
    always_ff @(posedge clk)begin
        if(!rst_n)begin pending<=0;negative<=0;end
        else begin
            pending<={pending[4:0],valid};negative<={negative[4:0],a[63]^b[63]};
        end
        // Enable each stage to avoid needless switching while scalar work runs.
        // Isolate RAM-bank selection and lag subtraction from absolute-value carry.
        if(valid)begin raw_a<=a;raw_b<=b;end
        if(pending[0])begin
            aa<=raw_a[63] ? (~$unsigned(raw_a)+64'd1) : $unsigned(raw_a);
            bb<=raw_b[63] ? (~$unsigned(raw_b)+64'd1) : $unsigned(raw_b);
        end
        if(pending[1])begin
            p00<=aa[31:0]*bb[31:0];p01<=aa[31:0]*bb[63:32];
            p10<=aa[63:32]*bb[31:0];p11<=aa[63:32]*bb[63:32];
        end
        if(pending[2])begin
            lo<={64'd0,p00}+({64'd0,p01}<<32);
            hi<=({64'd0,p10}<<32)+({64'd0,p11}<<64);
        end
        if(pending[3])magnitude<=lo+hi;
        // Register sign correction and rounding before the accumulator/SOS adders.
        if(pending[4])begin
            output_product<=negative[4] ? $signed(~magnitude+128'd1) : $signed(magnitude);
            output_rounded<=negative[4] ? -$signed(q[63:0]) : $signed(q[63:0]);
            output_overflow<=q>(negative[4] ? 128'h8000000000000000 : 128'h7fffffffffffffff);
        end
    end
endmodule
