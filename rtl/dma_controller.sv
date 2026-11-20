`timescale 1ns/1ps
`default_nettype none
// 32-bit memory copy engine. Four-word buffered bursts, one outstanding beat.
// Custom completion bus: valid && ready completes a read/write on the same edge.
module dma_controller # (parameter integer BURST_WORDS=4) (
    input wire clk, input wire rst_n,
    input wire reg_valid, input wire reg_write,
    input wire [7:0] reg_addr, input wire [31:0] reg_wdata,
    output wire reg_ready, output reg [31:0] reg_rdata, output wire irq,
    output wire m_valid, output wire m_write,
    output wire [31:0] m_addr, output wire [31:0] m_wdata,
    input wire m_ready, input wire [31:0] m_rdata, input wire m_error
);
    localparam [1:0] IDLE=0, READ=1, WRITE=2;
    reg [1:0] state;
    reg [31:0] src_cfg,dst_cfg,len_cfg,timeout_cfg;
    reg [31:0] src,dst,remaining,completed,watchdog,active_timeout;
    reg [31:0] buffer [0:BURST_WORDS-1];
    integer index, group_size;
    reg done,error,irq_en;
    reg [2:0] error_code;
    wire busy=state!=IDLE;
    wire wr=reg_valid && reg_write;
    wire [34:0] src_end={3'b0,src_cfg}+{1'b0,len_cfg,2'b0};
    wire [34:0] dst_end={3'b0,dst_cfg}+{1'b0,len_cfg,2'b0};
    wire overlap=({3'b0,src_cfg}<dst_end) && ({3'b0,dst_cfg}<src_end);
    wire invalid_cfg=(src_cfg[1:0]!=0)||(dst_cfg[1:0]!=0)||
        (src_end>35'h100000000)||(dst_end>35'h100000000)||overlap;
    assign reg_ready=1'b1;
    assign irq=irq_en && done;
    assign m_valid=busy;
    assign m_write=state==WRITE;
    assign m_addr=state==WRITE ? dst : src;
    assign m_wdata=buffer[index];
    always @* begin
        reg_rdata=0;
        case(reg_addr)
            8'h04: reg_rdata={26'b0,error_code,error,done,busy};
            8'h08: reg_rdata=src_cfg;
            8'h0c: reg_rdata=dst_cfg;
            8'h10: reg_rdata=len_cfg;
            8'h14: reg_rdata=completed;
            8'h18: reg_rdata={31'b0,irq_en};
            8'h1c: reg_rdata=timeout_cfg;
            8'h20: reg_rdata=32'h444d4101;
            default: reg_rdata=0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; src_cfg<=0; dst_cfg<=0; len_cfg<=0; timeout_cfg<=1_000_000;
            src<=0; dst<=0; remaining<=0; completed<=0; watchdog<=0; active_timeout<=1_000_000;
            index<=0; group_size<=1; done<=0; error<=0; error_code<=0; irq_en<=0;
        end else begin
            if(wr && reg_addr==8'h04) begin
                if(reg_wdata[1]) done<=0;
                if(reg_wdata[2]) begin error<=0; error_code<=0; end
            end
            if(wr && reg_addr==8'h18) irq_en<=reg_wdata[0];
            if(!busy) begin
                if(wr && reg_addr==8'h08) src_cfg<=reg_wdata;
                if(wr && reg_addr==8'h0c) dst_cfg<=reg_wdata;
                if(wr && reg_addr==8'h10) len_cfg<=reg_wdata;
                if(wr && reg_addr==8'h1c) timeout_cfg<=reg_wdata==0 ? 32'd1 : reg_wdata;
                if(wr && reg_addr==8'h00 && reg_wdata[0]) begin
                    done<=0; error<=0; error_code<=0; completed<=0; watchdog<=0;
                    if(len_cfg==0) done<=1;
                    else if(invalid_cfg) begin done<=1; error<=1; error_code<=1; end
                    else begin
                        src<=src_cfg; dst<=dst_cfg; remaining<=len_cfg;
                        active_timeout<=timeout_cfg; index<=0;
                        group_size<=len_cfg<BURST_WORDS ? len_cfg : BURST_WORDS;
                        state<=READ;
                    end
                end
            end else if(m_ready) begin
                watchdog<=0;
                if(m_error) begin state<=IDLE; done<=1; error<=1; error_code<=2; end
                else if(state==READ) begin
                    buffer[index]<=m_rdata; src<=src+4;
                    if(index==group_size-1) begin index<=0; state<=WRITE; end
                    else index<=index+1;
                end else begin
                    dst<=dst+4; remaining<=remaining-1'b1; completed<=completed+1'b1;
                    if(remaining==1) begin state<=IDLE; done<=1; index<=0; end
                    else if(index==group_size-1) begin
                        index<=0; state<=READ;
                        group_size<=(remaining-1)<BURST_WORDS ? remaining-1 : BURST_WORDS;
                    end else index<=index+1;
                end
            end else if(watchdog>=active_timeout-1'b1) begin
                state<=IDLE; done<=1; error<=1; error_code<=3; watchdog<=0;
            end else watchdog<=watchdog+1'b1;
        end
    end
endmodule
`default_nettype wire
