`timescale 1ns/1ps
`default_nettype none
// Entire demo is in FPGA fabric. The small sequencer is the CPU stand-in.
module de10_dma_top(input wire MAX10_CLK1_50,input wire KEY0,output wire [9:0] LEDR);
    wire clk=MAX10_CLK1_50;wire rst_n;
    reset_release resetter(clk,KEY0,rst_n);
    reg rv,rw;reg [7:0] ra;reg [31:0] wd;wire [31:0] rd;wire unused_status=^rd;wire unused_ready,unused_irq;
    wire dv,dw,dr,de;wire [31:0] da,dd,dread;
    dma_controller core(.clk(clk),.rst_n(rst_n),.reg_valid(rv),.reg_write(rw),.reg_addr(ra),
        .reg_wdata(wd),.reg_ready(unused_ready),.reg_rdata(rd),.irq(unused_irq),
        .m_valid(dv),.m_write(dw),.m_addr(da),.m_wdata(dd),.m_ready(dr),.m_rdata(dread),.m_error(de));
    reg cv,cw;reg [31:0] ca,cd;wire cr,ce;wire [31:0] cread;
    wire mv,mw;wire [31:0] ma,md;wire mr,me;reg [31:0] mread;
    rr_arbiter arb(.clk(clk),.rst_n(rst_n),.a_valid(dv),.a_write(dw),.a_addr(da),.a_wdata(dd),
        .a_ready(dr),.a_rdata(dread),.a_error(de),.b_valid(cv),.b_write(cw),.b_addr(ca),.b_wdata(cd),
        .b_ready(cr),.b_rdata(cread),.b_error(ce),.m_valid(mv),.m_write(mw),.m_addr(ma),.m_wdata(md),
        .m_ready(mr),.m_rdata(mread),.m_error(me));
    reg [31:0] ram[0:255];reg pending;
    assign mr=pending && mv;
    assign me=ma[31:10]!=0 || ma[1:0]!=0;
    // Synchronous RAM read; ready follows one cycle after seeing the request.
    always @(posedge clk) begin
        if(mv && !pending) mread<=ram[ma[9:2]];
        if(mv && mr && mw && !me) ram[ma[9:2]]<=md;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)pending<=0;
        else if(!mv || mr)pending<=0;
        else pending<=1;
    end
    localparam INIT=0,SOURCE=1,DEST=2,LENGTH=3,START=4,RUN=5,VERIFY=6,HALT=7;
    reg [2:0] state;reg [7:0] index;reg passed,failed;reg [7:0] checked;
    assign LEDR={failed,passed,checked};
    always @* begin
        rv=0;rw=0;ra=4;wd=0;cv=0;cw=0;ca=0;cd=0;
        case(state)
            INIT:begin cv=1;cw=1;ca={22'b0,index,2'b0};cd=index<64 ? (32'ha5000000^{24'b0,index}) : 0;end
            SOURCE:begin rv=1;rw=1;ra=8;wd=0;end
            DEST:begin rv=1;rw=1;ra=12;wd=512;end
            LENGTH:begin rv=1;rw=1;ra=16;wd=64;end
            START:begin rv=1;rw=1;ra=0;wd=1;end
            RUN:begin rv=1;ra=4;cv=1;ca=1020;end
            VERIFY:begin cv=1;ca=512+{22'b0,index,2'b0};end
            default:begin end
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin state<=INIT;index<=0;passed<=0;failed<=0;checked<=0;end
        else case(state)
            INIT:if(cr)begin if(ce)begin failed<=1;state<=HALT;end
                else if(index==255)begin index<=0;state<=SOURCE;end else index<=index+1'b1;end
            SOURCE:state<=DEST;
            DEST:state<=LENGTH;
            LENGTH:state<=START;
            START:state<=RUN;
            // Finish the current CPU beat before changing its address.
            RUN:if(rd[1] && cr)begin
                if(rd[2]||ce)begin failed<=1;state<=HALT;end
                else begin index<=0;state<=VERIFY;end
            end
            VERIFY:if(cr)begin
                if(ce || cread!=(32'ha5000000^{24'b0,index}))begin failed<=1;state<=HALT;end
                else begin checked<=checked+1'b1;
                    if(index==63)begin passed<=1;state<=HALT;end else index<=index+1'b1;
                end
            end
            default:state<=HALT;
        endcase
    end
endmodule
`default_nettype wire
