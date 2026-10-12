`timescale 1ns/1ps

module tb_attention_ip;

    localparam CLK_PERIOD = 20;

    reg clk;
    reg reset_n;
    reg start;
    reg [2:0]query_index;
    reg signed [7:0]q_in;
    reg signed [7:0]k_in;
    reg signed [7:0]v_in;
    reg q_valid;
    reg kv_valid;

    wire data_ready;
    wire signed [7:0]out_data;
    wire out_valid;
    wire done;

    attention_ip attention_ip (
        .clk         (clk),
        .reset_n     (reset_n),
        .start       (start),
        .query_index (query_index),
        .q_in        (q_in),
        .k_in        (k_in),
        .v_in        (v_in),
        .q_valid     (q_valid),
        .kv_valid    (kv_valid),
        .data_ready  (data_ready),
        .out_data    (out_data),
        .out_valid   (out_valid),
        .done        (done)
    );

    reg signed [7:0]q_buffer[0:3];
    reg signed [7:0]k_buffer[0:31];
    reg signed [7:0]v_buffer[0:31];
    reg signed [7:0]expected_output[0:3];
    reg signed [17:0]expected_x_max;

    integer error_count;
    integer test_count;
    integer case_id;
    integer errors_before_case;

    always #(CLK_PERIOD/2) clk = ~clk;

    task clear_vectors;
        integer i;
        begin
            query_index = 3'd0;
            expected_x_max = 18'sd0;

            for (i = 0; i < 4; i = i + 1) begin
                q_buffer[i] = 8'sd0;
                expected_output[i] = 8'sd0;
            end

            for (i = 0; i < 32; i = i + 1) begin
                k_buffer[i] = 8'sd0;
                v_buffer[i] = 8'sd0;
            end
        end
    endtask

    // 四组定向用例覆盖序列首位、中间位置、多最大值和末位兼容性。
    task load_test_case;
        input integer test_id;
        integer token;
        begin
            clear_vectors;

            case (test_id)
                // i=0：只有 Key[0] 可见。未来 Key 的 Score 全部更大，
                // 用于检查它们既不能参与 MAX，也不能产生 Weight。
                1: begin
                    query_index = 3'd0;
                    q_buffer[0] = 8'sd1;
                    k_buffer[0] = 8'sd0;

                    v_buffer[0] = 8'sd11;
                    v_buffer[1] = -8'sd12;
                    v_buffer[2] = 8'sd13;
                    v_buffer[3] = -8'sd14;

                    for (token = 1; token < 8; token = token + 1) begin
                        k_buffer[token*4] = 10 + token;
                        v_buffer[token*4] = 80 + token;
                    end

                    expected_x_max = 18'sd0;
                    expected_output[0] = 8'sd11;
                    expected_output[1] = -8'sd12;
                    expected_output[2] = 8'sd13;
                    expected_output[3] = -8'sd14;
                end

                // i=3：允许区间 Score 为 0、1、2、3，未来 Score 为 24～27。
                // 正确权重应为 1、2、6、16，未来四项全部为 0。
                2: begin
                    query_index = 3'd3;
                    q_buffer[0] = 8'sd1;

                    for (token = 0; token < 4; token = token + 1)
                        k_buffer[token*4] = token;
                    for (token = 4; token < 8; token = token + 1)
                        k_buffer[token*4] = 20 + token;

                    v_buffer[4]  = 8'sd10;
                    v_buffer[9]  = 8'sd10;
                    v_buffer[14] = 8'sd10;

                    expected_x_max = 18'sd3;
                    expected_output[0] = 8'sd1;
                    expected_output[1] = 8'sd2;
                    expected_output[2] = 8'sd6;
                    expected_output[3] = 8'sd0;
                end

                // i=3 且所有 Score 相同：只平均 V[0]～V[3]，
                // 验证多最大值情况下未来 Token 仍被屏蔽。
                3: begin
                    query_index = 3'd3;

                    v_buffer[0]  = 8'sd1;
                    v_buffer[1]  = -8'sd1;
                    v_buffer[2]  = 8'sd0;
                    v_buffer[3]  = 8'sd4;
                    v_buffer[4]  = 8'sd3;
                    v_buffer[5]  = -8'sd3;
                    v_buffer[6]  = 8'sd2;
                    v_buffer[7]  = -8'sd4;
                    v_buffer[8]  = 8'sd5;
                    v_buffer[9]  = -8'sd5;
                    v_buffer[10] = 8'sd4;
                    v_buffer[11] = 8'sd4;
                    v_buffer[12] = 8'sd7;
                    v_buffer[13] = -8'sd7;
                    v_buffer[14] = 8'sd6;
                    v_buffer[15] = -8'sd4;

                    for (token = 4; token < 8; token = token + 1) begin
                        v_buffer[token*4]     = 8'sd100;
                        v_buffer[token*4 + 1] = -8'sd100;
                        v_buffer[token*4 + 2] = 8'sd100;
                        v_buffer[token*4 + 3] = 8'sd100;
                    end

                    expected_x_max = 18'sd0;
                    expected_output[0] = 8'sd4;
                    expected_output[1] = -8'sd4;
                    expected_output[2] = 8'sd3;
                    expected_output[3] = 8'sd0;
                end

                // i=7：没有未来 Key，输出应与基础版完全一致。
                4: begin
                    query_index = 3'd7;
                    for (token = 0; token < 8; token = token + 1) begin
                        v_buffer[token*4]     = token + 1;
                        v_buffer[token*4 + 1] = -(token + 1);
                        v_buffer[token*4 + 2] = 8'sd3;
                        if ((token % 2) == 0)
                            v_buffer[token*4 + 3] = 8'sd2;
                        else
                            v_buffer[token*4 + 3] = -8'sd2;
                    end

                    expected_x_max = 18'sd0;
                    expected_output[0] = 8'sd5;
                    expected_output[1] = -8'sd5;
                    expected_output[2] = 8'sd3;
                    expected_output[3] = 8'sd0;
                end

                default: begin
                    $display("[ERROR] 未定义的测试编号：%0d", test_id);
                    error_count = error_count + 1;
                end
            endcase
        end
    endtask

    task send_input_vectors;
        input integer insert_stalls;
        integer i;
        begin
            q_valid = 1'b0;
            kv_valid = 1'b0;

            for (i = 0; i < 4; i = i + 1) begin
                if ((insert_stalls != 0) && (i == 2)) begin
                    q_valid = 1'b0;
                    @(negedge clk);
                end
                while (data_ready !== 1'b1)
                    @(negedge clk);
                q_in = q_buffer[i];
                q_valid = 1'b1;
                @(negedge clk);
            end
            q_valid = 1'b0;
            q_in = 8'sd0;

            for (i = 0; i < 32; i = i + 1) begin
                if ((insert_stalls != 0) && ((i % 7) == 3)) begin
                    kv_valid = 1'b0;
                    @(negedge clk);
                end
                while (data_ready !== 1'b1)
                    @(negedge clk);
                k_in = k_buffer[i];
                v_in = v_buffer[i];
                kv_valid = 1'b1;
                @(negedge clk);
            end
            kv_valid = 1'b0;
            k_in = 8'sd0;
            v_in = 8'sd0;
        end
    endtask

    task compare_outputs;
        input integer test_id;
        integer output_count;
        begin
            output_count = 0;
            while (output_count < 4) begin
                @(negedge clk);
                if (out_valid === 1'b1) begin
                    if ((^out_data === 1'bx) ||
                        ($signed(out_data) !=
                         $signed(expected_output[output_count]))) begin
                        $display(
                            "[ERROR][case %0d] O[%0d]: RTL=%0d, 期望=%0d",
                            test_id,
                            output_count,
                            $signed(out_data),
                            $signed(expected_output[output_count])
                        );
                        error_count = error_count + 1;
                    end
                    else begin
                        $display("[INFO ][case %0d] O[%0d]=%0d",
                                 test_id,
                                 output_count,
                                 $signed(out_data));
                    end
                    output_count = output_count + 1;
                end
            end
        end
    endtask

    // 直接检查因果 Mask 的关键内部结果，作为独立结构验证。
    task check_mask_state;
        input integer test_id;
        integer token;
        begin
            if ($signed(attention_ip.x_max) != $signed(expected_x_max)) begin
                $display("[ERROR][case %0d] x_max=%0d, 期望=%0d",
                         test_id,
                         $signed(attention_ip.x_max),
                         $signed(expected_x_max));
                error_count = error_count + 1;
            end

            for (token = query_index + 1; token < 8; token = token + 1) begin
                if (attention_ip.weight_buf[token] !== 5'd0) begin
                    $display("[ERROR][case %0d] 被屏蔽的 Weight[%0d]=%0d",
                             test_id,
                             token,
                             attention_ip.weight_buf[token]);
                    error_count = error_count + 1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset_n = 1'b0;
        start = 1'b0;
        query_index = 3'd0;
        q_in = 8'sd0;
        k_in = 8'sd0;
        v_in = 8'sd0;
        q_valid = 1'b0;
        kv_valid = 1'b0;
        error_count = 0;
        test_count = 0;

        for (case_id = 1; case_id <= 4; case_id = case_id + 1) begin
            test_count = test_count + 1;
            errors_before_case = error_count;
            load_test_case(case_id);

            reset_n = 1'b0;
            start = 1'b0;
            q_valid = 1'b0;
            kv_valid = 1'b0;
            repeat (3) @(negedge clk);
            reset_n = 1'b1;
            @(negedge clk);

            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            send_input_vectors((case_id % 2) == 0);
            compare_outputs(case_id);
            check_mask_state(case_id);

            if (error_count == errors_before_case)
                $display("[PASS ][case %0d] query_index=%0d",
                         case_id, query_index);
            else
                $display("[FAIL ][case %0d] 新增错误=%0d",
                         case_id, error_count-errors_before_case);

            $display("--------------------------------------------------");
        end

        if (error_count == 0) begin
            $display("==================================================");
            $display("TESTBENCH PASS: %0d cases, 0 errors", test_count);
            $display("==================================================");
        end
        else begin
            $display("==================================================");
            $display("TESTBENCH FAIL: %0d cases, %0d errors",
                     test_count, error_count);
            $display("==================================================");
        end

        #20;
        $finish;
    end

    initial begin
        #200000;
        $display("[ERROR] 仿真超时");
        $finish;
    end

endmodule
