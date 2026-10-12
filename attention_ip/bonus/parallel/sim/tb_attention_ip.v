`timescale 1ns/1ps

module tb_attention_ip;

    localparam CLK_PERIOD = 20;
    localparam EXPECTED_COMPUTE_CYCLES = 39;
    localparam EXPECTED_TOTAL_CYCLES = 75;

    reg clk;
    reg reset_n;
    reg start;
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
        .clk        (clk),
        .reset_n    (reset_n),
        .start      (start),
        .q_in       (q_in),
        .k_in       (k_in),
        .v_in       (v_in),
        .q_valid    (q_valid),
        .kv_valid   (kv_valid),
        .data_ready (data_ready),
        .out_data   (out_data),
        .out_valid  (out_valid),
        .done       (done)
    );

    //输入缓存寄存器
    reg signed [7:0]q_buffer[0:3];
    reg signed [7:0]k_buffer[0:31];
    reg signed [7:0]v_buffer[0:31];

    //期望输出
    reg signed [7:0]expected_output[0:3];

    integer error_count;
    integer test_count;
    integer case_id;
    integer errors_before_case;
    integer cycle_counter;
    integer compute_start_cycle;
    integer compute_cycles;
    integer task_start_cycle;
    integer total_cycles;

    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            cycle_counter <= 0;
        else
            cycle_counter <= cycle_counter + 1;
    end

    task clear_vectors;
        integer i;
        begin
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

    //3组定向测试和1组固定种子随机测试
    task load_test_case;
        input integer test_id;
        integer i;
        integer token;
        begin
            clear_vectors;

            case (test_id)
                //所有 Score 相同，检查多最大值和正负 .5 舍入。
                1: begin
                    for (token = 0; token < 8; token = token + 1) begin
                        v_buffer[token*4]     = token + 1;
                        v_buffer[token*4 + 1] = -(token + 1);
                        v_buffer[token*4 + 2] = 8'sd3;
                        if ((token % 2) == 0)
                            v_buffer[token*4 + 3] = 8'sd2;
                        else
                            v_buffer[token*4 + 3] = -8'sd2;
                    end

                    expected_output[0] =  8'sd5;
                    expected_output[1] = -8'sd5;
                    expected_output[2] =  8'sd3;
                    expected_output[3] =  8'sd0;
                end

                //覆盖全部 LUT 档位。
                2: begin
                    q_buffer[0] = 8'sd1;
                    for (token = 0; token < 8; token = token + 1) begin
                        k_buffer[token*4]     = 3 - token;
                        v_buffer[token*4]     = token;
                        v_buffer[token*4 + 1] = 7 - token;
                        if ((token % 2) == 0)
                            v_buffer[token*4 + 2] = 8'sd4;
                        else
                            v_buffer[token*4 + 2] = -8'sd4;
                        v_buffer[token*4 + 3] = -token;
                    end

                    expected_output[0] =  8'sd1;
                    expected_output[1] =  8'sd6;
                    expected_output[2] =  8'sd2;
                    expected_output[3] = -8'sd1;
                end

                // 8位有符号极值，检查符号扩展和18位 Score。
                3: begin
                    for (i = 0; i < 4; i = i + 1) begin
                        q_buffer[i] = 8'sh80;
                        k_buffer[i] = 8'sh80;
                    end

                    v_buffer[0] = 8'sh80;
                    v_buffer[1] = 8'sd127;
                    v_buffer[2] = -8'sd1;
                    v_buffer[3] = 8'sd1;

                    for (token = 1; token < 8; token = token + 1) begin
                        for (i = 0; i < 4; i = i + 1)
                            k_buffer[token*4 + i] = 8'sd127;
                    end

                    expected_output[0] = 8'sh80;
                    expected_output[1] = 8'sd127;
                    expected_output[2] = -8'sd1;
                    expected_output[3] = 8'sd1;
                end

                // Python固定种子3生成的小范围随机用例。
                4: begin
                    q_buffer[0] = -8'sd1;
                    q_buffer[1] =  8'sd4;
                    q_buffer[2] = -8'sd2;
                    q_buffer[3] =  8'sd1;

                    k_buffer[0]  =  8'sd3;
                    k_buffer[1]  = -8'sd3;
                    k_buffer[2]  = -8'sd4;
                    k_buffer[3]  =  8'sd3;
                    k_buffer[4]  =  8'sd0;
                    k_buffer[5]  =  8'sd4;
                    k_buffer[6]  = -8'sd1;
                    k_buffer[7]  = -8'sd1;
                    k_buffer[8]  =  8'sd3;
                    k_buffer[9]  =  8'sd4;
                    k_buffer[10] =  8'sd4;
                    k_buffer[11] =  8'sd3;
                    k_buffer[12] =  8'sd2;
                    k_buffer[13] = -8'sd2;
                    k_buffer[14] = -8'sd1;
                    k_buffer[15] = -8'sd2;
                    k_buffer[16] =  8'sd4;
                    k_buffer[17] =  8'sd2;
                    k_buffer[18] = -8'sd4;
                    k_buffer[19] = -8'sd3;
                    k_buffer[20] = -8'sd2;
                    k_buffer[21] = -8'sd4;
                    k_buffer[22] =  8'sd0;
                    k_buffer[23] = -8'sd4;
                    k_buffer[24] =  8'sd0;
                    k_buffer[25] =  8'sd3;
                    k_buffer[26] =  8'sd2;
                    k_buffer[27] =  8'sd2;
                    k_buffer[28] =  8'sd2;
                    k_buffer[29] =  8'sd3;
                    k_buffer[30] = -8'sd2;
                    k_buffer[31] =  8'sd1;

                    v_buffer[0]  = -8'sd20;
                    v_buffer[1]  = -8'sd28;
                    v_buffer[2]  = -8'sd15;
                    v_buffer[3]  =  8'sd31;
                    v_buffer[4]  = -8'sd5;
                    v_buffer[5]  =  8'sd1;
                    v_buffer[6]  =  8'sd23;
                    v_buffer[7]  =  8'sd6;
                    v_buffer[8]  =  8'sd21;
                    v_buffer[9]  =  8'sd17;
                    v_buffer[10] =  8'sd12;
                    v_buffer[11] =  8'sd20;
                    v_buffer[12] = -8'sd3;
                    v_buffer[13] =  8'sd11;
                    v_buffer[14] = -8'sd29;
                    v_buffer[15] =  8'sd3;
                    v_buffer[16] = -8'sd12;
                    v_buffer[17] =  8'sd9;
                    v_buffer[18] = -8'sd19;
                    v_buffer[19] = -8'sd5;
                    v_buffer[20] =  8'sd2;
                    v_buffer[21] =  8'sd4;
                    v_buffer[22] = -8'sd17;
                    v_buffer[23] = -8'sd24;
                    v_buffer[24] =  8'sd29;
                    v_buffer[25] =  8'sd29;
                    v_buffer[26] = -8'sd21;
                    v_buffer[27] =  8'sd12;
                    v_buffer[28] = -8'sd24;
                    v_buffer[29] =  8'sd20;
                    v_buffer[30] = -8'sd13;
                    v_buffer[31] = -8'sd30;

                    expected_output[0] = -8'sd7;
                    expected_output[1] =  8'sd3;
                    expected_output[2] =  8'sd19;
                    expected_output[3] =  8'sd2;
                end

                default: begin
                    $display("[ERROR] 未定义的测试编号：%0d", test_id);
                    error_count = error_count + 1;
                end
            endcase
        end
    endtask

    // 按 ready/valid 协议发送 Q、K、V。
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

    //在out_valid有效时收集并核对4个输出
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

    initial begin
        clk = 1'b0;
        reset_n = 1'b0;
        start = 1'b0;
        q_in = 8'sd0;
        k_in = 8'sd0;
        v_in = 8'sd0;
        q_valid = 1'b0;
        kv_valid = 1'b0;
        error_count = 0;
        test_count = 0;
        cycle_counter = 0;
        compute_start_cycle = 0;
        compute_cycles = 0;
        task_start_cycle = 0;
        total_cycles = 0;

        for (case_id = 1; case_id <= 4; case_id = case_id + 1) begin
            test_count = test_count + 1;
            errors_before_case = error_count;
            load_test_case(case_id);

            // 复位时序
            reset_n = 1'b0;
            start = 1'b0;
            q_valid = 1'b0;
            kv_valid = 1'b0;
            repeat (3) @(negedge clk);
            reset_n = 1'b1;
            @(negedge clk);

            //start 脉冲
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            task_start_cycle = cycle_counter;

            // 偶数编号用例插入 valid 空拍。
            send_input_vectors((case_id % 2) == 0);
            compute_start_cycle = cycle_counter;
            compare_outputs(case_id);
            compute_cycles = cycle_counter - compute_start_cycle;
            total_cycles = cycle_counter - task_start_cycle;

            if (compute_cycles != EXPECTED_COMPUTE_CYCLES) begin
                $display("[ERROR][case %0d] COMPUTE_CYCLES=%0d, EXPECTED=%0d",
                         case_id,
                         compute_cycles,
                         EXPECTED_COMPUTE_CYCLES);
                error_count = error_count + 1;
            end
            else begin
                $display("[INFO ][case %0d] COMPUTE_CYCLES=%0d",
                         case_id,
                         compute_cycles);
            end

            if ((case_id % 2) != 0) begin
                if (total_cycles != EXPECTED_TOTAL_CYCLES) begin
                    $display("[ERROR][case %0d] TOTAL_CYCLES=%0d, EXPECTED=%0d",
                             case_id,
                             total_cycles,
                             EXPECTED_TOTAL_CYCLES);
                    error_count = error_count + 1;
                end
                else begin
                    $display("[INFO ][case %0d] TOTAL_CYCLES=%0d",
                             case_id,
                             total_cycles);
                end
            end
            else begin
                $display("[INFO ][case %0d] TOTAL_CYCLES_WITH_INPUT_STALLS=%0d",
                         case_id,
                         total_cycles);
            end

            if (error_count == errors_before_case)
                $display("[PASS ][case %0d]", case_id);
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

endmodule
