# GUI 模式：自动加入主要波形，运行完成后保持界面打开。
onerror {resume}
onfinish stop

view wave
delete wave *

configure wave -namecolwidth 260
configure wave -valuecolwidth 110
configure wave -timelineunits ns

# Testbench 只显示与 DUT 连接的输入输出端口。
add wave -group {TB Interface} -radix binary sim:/tb_attention_ip/clk
add wave -group {TB Interface} -radix binary sim:/tb_attention_ip/reset_n
add wave -group {TB Interface} -radix binary sim:/tb_attention_ip/start
add wave -group {TB Interface} -radix decimal sim:/tb_attention_ip/q_in
add wave -group {TB Interface} -radix decimal sim:/tb_attention_ip/k_in
add wave -group {TB Interface} -radix decimal sim:/tb_attention_ip/v_in
add wave -group {TB Interface} -radix binary sim:/tb_attention_ip/q_valid
add wave -group {TB Interface} -radix binary sim:/tb_attention_ip/kv_valid
add wave -group {TB Interface} -radix binary sim:/tb_attention_ip/data_ready
add wave -group {TB Interface} -radix decimal sim:/tb_attention_ip/out_data
add wave -group {TB Interface} -radix binary sim:/tb_attention_ip/out_valid
add wave -group {TB Interface} -radix binary sim:/tb_attention_ip/done

# attention_ip 中的状态寄存器和全部计数器。
add wave -group {DUT Control Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/state
add wave -group {DUT Control Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/cnt_q
add wave -group {DUT Control Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/cnt_kv
add wave -group {DUT Control Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/cnt_dim
add wave -group {DUT Control Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/cnt_token
add wave -group {DUT Control Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/cnt_max
add wave -group {DUT Control Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/cnt_exp
add wave -group {DUT Control Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/cnt_update
add wave -group {DUT Control Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/cnt_output

# 输入缓存寄存器，按数组类型分组，便于折叠。
for {set i 0} {$i < 4} {incr i} {
    add wave -group {DUT Q Buffer Registers} -radix decimal sim:/tb_attention_ip/attention_ip/q_buffer($i)
}
for {set i 0} {$i < 32} {incr i} {
    add wave -group {DUT K Buffer Registers} -radix decimal sim:/tb_attention_ip/attention_ip/k_buffer($i)
}
for {set i 0} {$i < 32} {incr i} {
    add wave -group {DUT V Buffer Registers} -radix decimal sim:/tb_attention_ip/attention_ip/v_buffer($i)
}

# Score、Weight 及 Softmax 相关寄存器。
for {set i 0} {$i < 8} {incr i} {
    add wave -group {DUT Score Registers} -radix decimal sim:/tb_attention_ip/attention_ip/score_buf($i)
}
for {set i 0} {$i < 8} {incr i} {
    add wave -group {DUT Weight Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/weight_buf($i)
}
add wave -group {DUT Datapath Registers} -radix decimal sim:/tb_attention_ip/attention_ip/dot_acc
add wave -group {DUT Datapath Registers} -radix decimal sim:/tb_attention_ip/attention_ip/x_max
add wave -group {DUT Datapath Registers} -radix decimal sim:/tb_attention_ip/attention_ip/score_delta
add wave -group {DUT Datapath Registers} -radix unsigned sim:/tb_attention_ip/attention_ip/l_sum

# 四路 ACC 和最终结果寄存器。
for {set i 0} {$i < 4} {incr i} {
    add wave -group {DUT ACC Registers} -radix decimal sim:/tb_attention_ip/attention_ip/acc_buf($i)
}
for {set i 0} {$i < 4} {incr i} {
    add wave -group {DUT Result Registers} -radix decimal sim:/tb_attention_ip/attention_ip/result_buf($i)
}

# DUT 内部输出寄存器。
add wave -group {DUT Output Registers} -radix decimal sim:/tb_attention_ip/attention_ip/out_data_reg
add wave -group {DUT Output Registers} -radix binary sim:/tb_attention_ip/attention_ip/out_valid_reg
add wave -group {DUT Output Registers} -radix binary sim:/tb_attention_ip/attention_ip/done_reg

# round_div 函数中的临时寄存器。若仿真器优化掉某项，onerror resume 会继续执行。
add wave -group {DUT round_div Registers} -radix decimal sim:/tb_attention_ip/attention_ip/round_div/numerator_ext
add wave -group {DUT round_div Registers} -radix decimal sim:/tb_attention_ip/attention_ip/round_div/denominator_ext
add wave -group {DUT round_div Registers} -radix decimal sim:/tb_attention_ip/attention_ip/round_div/adjusted
add wave -group {DUT round_div Registers} -radix decimal sim:/tb_attention_ip/attention_ip/round_div/quotient

run -all
wave zoom full
