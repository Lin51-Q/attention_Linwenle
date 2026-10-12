module attention_ip (
    clk,
    reset_n,
    start,
    query_index,
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
    input [2:0]query_index;
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

    // 当前 Query 在长度为 8 的序列中的位置 i。
    // 因果 Mask 只允许访问 Key[0] 到 Key[i]。
    reg [2:0]query_index_reg;

    
    //输入缓存
    reg signed [7:0]q_buffer[0:3];
    reg signed [7:0]k_buffer[0:31];
    reg signed [7:0]v_buffer[0:31];

    
    //中间值寄存器
    reg signed [17:0]score_buf[0:7];
    reg        [4:0]weight_buf[0:7]; 

    reg signed [17:0]dot_acc;
    reg signed [17:0]x_max;
    reg signed [17:0]score_delta;

    reg        [7:0]l_sum;
    reg signed [15:0]acc_buf[0:3];
    reg signed [7:0]result_buf[0:3];

    //计数器
    reg [1:0]cnt_q;
    reg [5:0]cnt_kv;
    reg [1:0]cnt_dim;
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

    
    //当前点积和 UPDATE 阶段使用的展开地址
    wire [5:0]dot_kv_index;
    wire [5:0]update_base_index;

    assign dot_kv_index = {1'b0, cnt_token, 2'b00} + {4'b0000, cnt_dim};
    assign update_base_index = {1'b0, cnt_update, 2'b00};

    //q,k显式符号扩展
    wire signed [15:0]q_operand_ext;
    wire signed [15:0]k_operand_ext;
    wire signed [31:0]qk_product_full;
    wire signed [17:0]qk_product;

    //DOT阶段的点积计算
    assign q_operand_ext = {{8{q_buffer[cnt_dim][7]}}, q_buffer[cnt_dim]};
    assign k_operand_ext = {{8{k_buffer[dot_kv_index][7]}}, k_buffer[dot_kv_index]};
    assign qk_product_full = q_operand_ext * k_operand_ext;
    assign qk_product = qk_product_full[17:0];

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
            query_index_reg <= 3'd0;

            cnt_q        <= 2'd0;
            cnt_kv       <= 6'd0;
            cnt_dim      <= 2'd0;
            cnt_token    <= 3'd0;
            cnt_max      <= 3'd0;
            cnt_exp      <= 3'd0;
            cnt_update   <= 3'd0;
            cnt_output   <= 2'd0;

            dot_acc      <= 18'sd0;
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
                        // 在任务启动时锁存位置，后续计算不依赖输入端口继续保持。
                        query_index_reg <= query_index;
                        cnt_q       <= 2'd0;
                        cnt_kv      <= 6'd0;
                        cnt_dim     <= 2'd0;
                        cnt_token   <= 3'd0;
                        cnt_max     <= 3'd0;
                        cnt_exp     <= 3'd0;
                        cnt_update  <= 3'd0;
                        cnt_output  <= 2'd0;

                        dot_acc     <= 18'sd0;
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
                            cnt_dim   <= 2'd0;
                            dot_acc   <= 18'sd0;
                            state     <= DOT;
                        end
                        else 
                            cnt_kv <= cnt_kv + 6'd1;
                    end
                end

                DOT: begin
                    if (cnt_dim == 2'd3) begin
                        score_buf[cnt_token] <= dot_acc + qk_product;
                        dot_acc <= 18'sd0;
                        cnt_dim <= 2'd0;
                        state   <= NEXT;
                    end
                    else begin
                        dot_acc <= dot_acc + qk_product;
                        cnt_dim <= cnt_dim + 2'd1;
                    end
                end

                NEXT: begin
                    if (cnt_token == 3'd7) begin
                        x_max     <= score_buf[0];
                        cnt_max   <= 3'd1;
                        cnt_token <= 3'd0;
                        state     <= MAX;
                    end
                    else begin
                        cnt_token <= cnt_token + 3'd1;
                        state     <= DOT;
                    end
                end

                // 只在未被 Mask 的 Key[0] ~ Key[query_index_reg] 中找最大值。
                // 仍固定扫描 8 项，使加分版与基础版保持相同的控制周期。
                MAX: begin
                    if ((cnt_max <= query_index_reg) &&
                        (score_buf[cnt_max] > x_max))
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

                    // 因果 Mask：Key 下标 j 大于 Query 下标 i 时，权重强制为 0。
                    // 不能只在这里清零，还必须在 MAX 阶段排除未来 Key。
                    if (cnt_exp > query_index_reg)
                        weight_buf[cnt_exp] <= 5'd0;
                    else
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
