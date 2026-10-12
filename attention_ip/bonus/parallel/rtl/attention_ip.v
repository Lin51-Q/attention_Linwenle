module attention_ip (
    clk,
    reset_n,
    start,
    q_in,
    k_in,
    v_in,
    q_valid,
    kv_valid,
    data_ready,
    out_data,
    out_valid,
    done
);

    input clk;
    input reset_n;
    input start;
    input signed [7:0]q_in;
    input signed [7:0]k_in;
    input signed [7:0]v_in;
    input q_valid;
    input kv_valid;

    output data_ready;
    output signed [7:0]out_data;
    output out_valid;
    output done;

  
    //FSM状态定义
    localparam      IDLE    =   4'd0,
                    LOAD_Q  =   4'd1,
                    LOAD_KV =   4'd2,
                    DOT     =   4'd3,
                    MAX     =   4'd4,
                    EXP     =   4'd5,
                    UPDATE  =   4'd6,
                    NEXT    =   4'd7,
                    NORM    =   4'd8,
                    OUTPUT  =   4'd9;

    reg [3:0]state;

    
    //输入缓存
    reg signed [7:0]q_buffer[0:3];
    reg signed [7:0]k_buffer[0:31];
    reg signed [7:0]v_buffer[0:31];

    
    //中间值寄存器
    reg signed [17:0]score_buf[0:7];
    reg        [4:0]weight_buf[0:7]; 

    reg signed [17:0]x_max;
    reg signed [17:0]score_delta;

    reg        [7:0]l_sum;
    reg signed [15:0]acc_buf[0:3];
    reg signed [7:0]result_buf[0:3];

    //计数器
    reg [1:0]cnt_q;
    reg [5:0]cnt_kv;
    reg [2:0]cnt_token;
    reg [2:0]cnt_max;
    reg [2:0]cnt_exp;
    reg [2:0]cnt_update;
    reg [1:0]cnt_output;

    //输出寄存器
    reg signed [7:0]out_data_reg;
    reg out_valid_reg;
    reg done_reg;

    assign out_data  = out_data_reg;
    assign out_valid = out_valid_reg;
    assign done      = done_reg;
    assign data_ready = (state == LOAD_Q) || (state == LOAD_KV);

    
    // 当前 Token 的 K 起始地址和 UPDATE 阶段使用的展开地址
    wire [5:0]dot_base_index;
    wire [5:0]update_base_index;

    assign dot_base_index = {1'b0, cnt_token, 2'b00};
    assign update_base_index = {1'b0, cnt_update, 2'b00};

    // DOT 阶段使用 4 路并行乘法器和两级加法树。
    // 本版本每个 Token 只需要 1 个 DOT 周期。
    wire signed [15:0]q0_operand_ext;
    wire signed [15:0]q1_operand_ext;
    wire signed [15:0]q2_operand_ext;
    wire signed [15:0]q3_operand_ext;
    wire signed [15:0]k0_operand_ext;
    wire signed [15:0]k1_operand_ext;
    wire signed [15:0]k2_operand_ext;
    wire signed [15:0]k3_operand_ext;
    wire signed [31:0]qk_product0_full;
    wire signed [31:0]qk_product1_full;
    wire signed [31:0]qk_product2_full;
    wire signed [31:0]qk_product3_full;
    wire signed [17:0]qk_product0;
    wire signed [17:0]qk_product1;
    wire signed [17:0]qk_product2;
    wire signed [17:0]qk_product3;
    wire signed [18:0]qk_sum01;
    wire signed [18:0]qk_sum23;
    wire signed [19:0]dot_parallel_full;
    wire signed [17:0]dot_parallel;

    assign q0_operand_ext = {{8{q_buffer[0][7]}}, q_buffer[0]};
    assign q1_operand_ext = {{8{q_buffer[1][7]}}, q_buffer[1]};
    assign q2_operand_ext = {{8{q_buffer[2][7]}}, q_buffer[2]};
    assign q3_operand_ext = {{8{q_buffer[3][7]}}, q_buffer[3]};

    assign k0_operand_ext = {{8{k_buffer[dot_base_index][7]}},k_buffer[dot_base_index]};
    assign k1_operand_ext = {{8{k_buffer[dot_base_index + 6'd1][7]}},k_buffer[dot_base_index + 6'd1]};
    assign k2_operand_ext = {{8{k_buffer[dot_base_index + 6'd2][7]}},k_buffer[dot_base_index + 6'd2]};
    assign k3_operand_ext = {{8{k_buffer[dot_base_index + 6'd3][7]}},k_buffer[dot_base_index + 6'd3]};

    assign qk_product0_full = q0_operand_ext * k0_operand_ext;
    assign qk_product1_full = q1_operand_ext * k1_operand_ext;
    assign qk_product2_full = q2_operand_ext * k2_operand_ext;
    assign qk_product3_full = q3_operand_ext * k3_operand_ext;

    assign qk_product0 = qk_product0_full[17:0];
    assign qk_product1 = qk_product1_full[17:0];
    assign qk_product2 = qk_product2_full[17:0];
    assign qk_product3 = qk_product3_full[17:0];

    assign qk_sum01 = {{1{qk_product0[17]}}, qk_product0} + {{1{qk_product1[17]}}, qk_product1};
    assign qk_sum23 = {{1{qk_product2[17]}}, qk_product2} + {{1{qk_product3[17]}}, qk_product3};
    assign dot_parallel_full = {{1{qk_sum01[18]}}, qk_sum01} + {{1{qk_sum23[18]}}, qk_sum23};
    assign dot_parallel = dot_parallel_full[17:0];

    //把Weight处理成有符号数
    wire signed [15:0]weight_operand_ext;
    wire signed [15:0]v0_operand_ext;
    wire signed [15:0]v1_operand_ext;
    wire signed [15:0]v2_operand_ext;
    wire signed [15:0]v3_operand_ext;
    wire signed [31:0]wv_product0_full;
    wire signed [31:0]wv_product1_full;
    wire signed [31:0]wv_product2_full;
    wire signed [31:0]wv_product3_full;
    wire signed [15:0]wv_product0;
    wire signed [15:0]wv_product1;
    wire signed [15:0]wv_product2;
    wire signed [15:0]wv_product3;

    //w,v显式符号扩展
    assign weight_operand_ext = {11'd0, weight_buf[cnt_update]};
    assign v0_operand_ext = {{8{v_buffer[update_base_index][7]}} , v_buffer[update_base_index]};
    assign v1_operand_ext = {{8{v_buffer[update_base_index + 6'd1][7]}} , v_buffer[update_base_index + 6'd1]};
    assign v2_operand_ext = {{8{v_buffer[update_base_index + 6'd2][7]}} , v_buffer[update_base_index + 6'd2]};
    assign v3_operand_ext = {{8{v_buffer[update_base_index + 6'd3][7]}} , v_buffer[update_base_index + 6'd3]};

    // w*v计算
    assign wv_product0_full = weight_operand_ext * v0_operand_ext;
    assign wv_product1_full = weight_operand_ext * v1_operand_ext;
    assign wv_product2_full = weight_operand_ext * v2_operand_ext;
    assign wv_product3_full = weight_operand_ext * v3_operand_ext;

    //取低16位作为最终结果
    assign wv_product0 = wv_product0_full[15:0];
    assign wv_product1 = wv_product1_full[15:0];
    assign wv_product2 = wv_product2_full[15:0];
    assign wv_product3 = wv_product3_full[15:0];


    // 指数查找表(exp(delta))，delta为Q1.4格式，输出为Q1.4格式
    function [4:0]exp_lut;
        input signed [17:0]delta;
        begin
            if (delta >= 18'sd0)
                exp_lut = 5'd16; // 1.0000
            else if (delta == -18'sd1)
                exp_lut = 5'd6;  // 0.3750
            else if (delta == -18'sd2)
                exp_lut = 5'd2;  // 0.1250
            else if (delta == -18'sd3)
                exp_lut = 5'd1;  // 0.0625
            else
                exp_lut = 5'd0;
        end
    endfunction

    //NORM阶段的归一化除法器
    function signed [7:0]round_div;
        input signed [15:0]numerator;
        input        [7:0]denominator;

        reg signed [16:0]numerator_ext;
        reg signed [16:0]denominator_ext;
        reg signed [16:0]adjusted;
        reg signed [16:0]quotient;
        begin
            numerator_ext   = {numerator[15], numerator};
            denominator_ext = {9'd0, denominator};

            if (denominator == 8'd0) begin
                round_div = 8'sd0;
            end
            else begin
                if (numerator_ext >= 17'sd0)
                    adjusted = numerator_ext + (denominator_ext >>> 1);
                else
                    adjusted = numerator_ext - (denominator_ext >>> 1);

                quotient = adjusted / denominator_ext;
                round_div = quotient[7:0];
            end
        end
    endfunction

    //FSM
    always@(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= IDLE;

            cnt_q        <= 2'd0;
            cnt_kv       <= 6'd0;
            cnt_token    <= 3'd0;
            cnt_max      <= 3'd0;
            cnt_exp      <= 3'd0;
            cnt_update   <= 3'd0;
            cnt_output   <= 2'd0;

            x_max        <= 18'sd0;
            score_delta  <= 18'sd0;
            l_sum        <= 8'd0;

            acc_buf[0]   <= 16'sd0;
            acc_buf[1]   <= 16'sd0;
            acc_buf[2]   <= 16'sd0;
            acc_buf[3]   <= 16'sd0;

            out_data_reg <= 8'sd0;
            out_valid_reg <= 1'b0;
            done_reg      <= 1'b0;
        end
        else begin
            out_valid_reg <= 1'b0;
            done_reg      <= 1'b0;
            case(state)
                IDLE: begin
                    if (start) begin
                        cnt_q       <= 2'd0;
                        cnt_kv      <= 6'd0;
                        cnt_token   <= 3'd0;
                        cnt_max     <= 3'd0;
                        cnt_exp     <= 3'd0;
                        cnt_update  <= 3'd0;
                        cnt_output  <= 2'd0;

                        x_max       <= 18'sd0;
                        score_delta <= 18'sd0;
                        l_sum       <= 8'd0;

                        acc_buf[0]  <= 16'sd0;
                        acc_buf[1]  <= 16'sd0;
                        acc_buf[2]  <= 16'sd0;
                        acc_buf[3]  <= 16'sd0;

                        state       <= LOAD_Q;
                    end
                end

                LOAD_Q: begin
                    if (q_valid) begin
                        q_buffer[cnt_q] <= q_in;

                        if (cnt_q == 2'd3) begin
                            cnt_q  <= 2'd0;
                            cnt_kv <= 6'd0;
                            state  <= LOAD_KV;
                        end
                        else 
                            cnt_q <= cnt_q + 2'd1;
                    end
                end

                LOAD_KV: begin
                    if (kv_valid) begin
                        k_buffer[cnt_kv] <= k_in;
                        v_buffer[cnt_kv] <= v_in;

                        if (cnt_kv == 6'd31) begin
                            cnt_kv    <= 6'd0;
                            cnt_token <= 3'd0;
                            state     <= DOT;
                        end
                        else 
                            cnt_kv <= cnt_kv + 6'd1;
                    end
                end

                DOT: begin
                    score_buf[cnt_token] <= dot_parallel;

                    if (cnt_token == 3'd7) begin
                        x_max     <= score_buf[0];
                        cnt_max   <= 3'd1;
                        cnt_token <= 3'd0;
                        state     <= MAX;
                    end
                    else begin
                        cnt_token <= cnt_token + 3'd1;
                    end
                end

                // 并行版本不会进入 NEXT，保留状态编码便于与基础版波形对照。
                NEXT: begin
                    state <= DOT;
                end

                // 依次比较 score_buf[1] ~ score_buf[7]
                MAX: begin
                    if (score_buf[cnt_max] > x_max)
                        x_max <= score_buf[cnt_max];

                    if (cnt_max == 3'd7) begin
                        cnt_max <= 3'd0;
                        cnt_exp <= 3'd0;
                        state   <= EXP;
                    end
                    else 
                        cnt_max <= cnt_max + 3'd1;
                end

                EXP: begin
                    score_delta <= score_buf[cnt_exp] - x_max;
                    weight_buf[cnt_exp] <= exp_lut(score_buf[cnt_exp] - x_max);

                    if (cnt_exp == 3'd7) begin
                        cnt_exp    <= 3'd0;
                        cnt_update <= 3'd0;
                        l_sum      <= 8'd0;
                        acc_buf[0] <= 16'sd0;
                        acc_buf[1] <= 16'sd0;
                        acc_buf[2] <= 16'sd0;
                        acc_buf[3] <= 16'sd0;
                        state      <= UPDATE;
                    end
                    else begin
                        cnt_exp <= cnt_exp + 3'd1;
                    end
                end

                UPDATE: begin
                    l_sum <= l_sum + weight_buf[cnt_update];

                    acc_buf[0] <= acc_buf[0] + wv_product0;
                    acc_buf[1] <= acc_buf[1] + wv_product1;
                    acc_buf[2] <= acc_buf[2] + wv_product2;
                    acc_buf[3] <= acc_buf[3] + wv_product3;

                    if (cnt_update == 3'd7) begin
                        cnt_update <= 3'd0;
                        cnt_output <= 2'd0;
                        state      <= NORM;
                    end
                    else 
                        cnt_update <= cnt_update + 3'd1;
                end

                NORM: begin
                    result_buf[cnt_output] <= round_div(acc_buf[cnt_output], l_sum);

                    if (cnt_output == 2'd3) begin
                        cnt_output <= 2'd0;
                        state      <= OUTPUT;
                    end
                    else 
                        cnt_output <= cnt_output + 2'd1;
                end

                OUTPUT: begin
                    out_data_reg  <= result_buf[cnt_output];
                    out_valid_reg <= 1'b1;

                    if (cnt_output == 2'd3) begin
                        cnt_output <= 2'd0;
                        done_reg   <= 1'b1;
                        state      <= IDLE;
                    end
                    else 
                        cnt_output <= cnt_output + 2'd1;
                end

                default: 
                    state <= IDLE;
            endcase
        end
    end

endmodule
