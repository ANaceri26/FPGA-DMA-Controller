`timescale 1ns/1ps
`default_nettype none
// Fair, beat-level arbitration. A stalled grant is held until acceptance or cancellation.
module rr_arbiter (
    input wire clk, input wire rst_n,
    input wire a_valid,a_write, input wire [31:0] a_addr,a_wdata,
    output wire a_ready, output wire [31:0] a_rdata, output wire a_error,
    input wire b_valid,b_write, input wire [31:0] b_addr,b_wdata,
    output wire b_ready, output wire [31:0] b_rdata, output wire b_error,
    output wire m_valid,m_write, output wire [31:0] m_addr,m_wdata,
    input wire m_ready, input wire [31:0] m_rdata, input wire m_error
);
    reg prefer_b,locked,owner_b;
    wire choose_b=locked ? owner_b : (b_valid && (!a_valid || prefer_b));
    assign m_valid=choose_b ? b_valid : a_valid;
    assign m_write=choose_b ? b_write : a_write;
    assign m_addr=choose_b ? b_addr : a_addr;
    assign m_wdata=choose_b ? b_wdata : a_wdata;
    assign a_ready=m_ready && m_valid && !choose_b;
    assign b_ready=m_ready && m_valid && choose_b;
    assign a_rdata=m_rdata; assign b_rdata=m_rdata;
    assign a_error=m_error && a_ready; assign b_error=m_error && b_ready;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin prefer_b<=0; locked<=0; owner_b<=0; end
        else if(m_valid && m_ready) begin prefer_b<=!choose_b; locked<=0; end
        else if(m_valid) begin locked<=1; owner_b<=choose_b; end
        else locked<=0;
    end
endmodule
`default_nettype wire
