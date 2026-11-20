`timescale 1ns/1ps
module tb_dma #(parameter integer BURST_WORDS=4);
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,reg_valid=0,reg_write=0;
    reg [7:0] reg_addr=0;reg [31:0] reg_wdata=0;
    wire reg_ready,irq;wire [31:0] reg_rdata;
    wire d_valid,d_write,d_ready,d_error;wire [31:0] d_addr,d_wdata,d_rdata;
    reg c_valid=0,c_write=0;reg [31:0] c_addr=0,c_wdata=0;
    wire c_ready,c_error;wire [31:0] c_rdata;
    wire m_valid,m_write;wire [31:0] m_addr,m_wdata;
    reg m_ready=0,m_error=0;wire [31:0] m_rdata;
    reg [31:0] mem[0:1023];
    reg stalls=1,freeze=0,inject_error=0;
    reg [31:0] error_addr=0;
    integer seed=1,iterations=1000,k,j,n,t,cpu_count=0,beats=0;
    reg [31:0] st,rng;
    reg prev_stall=0,prev_write;reg [31:0] prev_addr,prev_data;
    dma_controller #(.BURST_WORDS(BURST_WORDS)) dut(.clk(clk),.rst_n(rst_n),.reg_valid(reg_valid),.reg_write(reg_write),
        .reg_addr(reg_addr),.reg_wdata(reg_wdata),.reg_ready(reg_ready),.reg_rdata(reg_rdata),.irq(irq),
        .m_valid(d_valid),.m_write(d_write),.m_addr(d_addr),.m_wdata(d_wdata),
        .m_ready(d_ready),.m_rdata(d_rdata),.m_error(d_error));
    rr_arbiter arb(.clk(clk),.rst_n(rst_n),.a_valid(d_valid),.a_write(d_write),.a_addr(d_addr),.a_wdata(d_wdata),
        .a_ready(d_ready),.a_rdata(d_rdata),.a_error(d_error),
        .b_valid(c_valid),.b_write(c_write),.b_addr(c_addr),.b_wdata(c_wdata),
        .b_ready(c_ready),.b_rdata(c_rdata),.b_error(c_error),
        .m_valid(m_valid),.m_write(m_write),.m_addr(m_addr),.m_wdata(m_wdata),
        .m_ready(m_ready),.m_rdata(m_rdata),.m_error(m_error));
    assign m_rdata=m_addr<4096 ? mem[m_addr[11:2]] : 32'hbad00000;
    always @(negedge clk) begin
        m_ready=!freeze && (!stalls || ($urandom_range(0,3)!=0));
    end
    always @* m_error=(m_addr>=4096)||(inject_error && m_addr==error_addr);
    always @(posedge clk) begin
        if(!rst_n) prev_stall<=0;
        else begin
            // A requester must keep its payload stable while waiting (unless it cancels).
            if(prev_stall && d_valid && (d_addr!==prev_addr || d_write!==prev_write || (d_write && d_wdata!==prev_data)))
                $fatal(1,"DMA changed pending payload");
            prev_stall<=d_valid && !d_ready;
            prev_addr<=d_addr;prev_write<=d_write;prev_data<=d_wdata;
            if(m_valid && m_ready && !m_error) begin
                beats<=beats+1;
                if(m_write) mem[m_addr[11:2]]<=m_wdata;
            end
            if(c_valid && c_ready) cpu_count<=cpu_count+1;
            if(c_ready && d_ready) $fatal(1,"double grant");
        end
    end
    task wr(input [7:0] a,input [31:0] d);
        begin @(negedge clk);reg_valid=1;reg_write=1;reg_addr=a;reg_wdata=d;
        @(negedge clk);reg_valid=0;reg_write=0;end
    endtask
    task rd(input [7:0] a,output [31:0] d);
        begin @(negedge clk);reg_addr=a;#1;d=reg_rdata;end
    endtask
    task launch(input [31:0] s,input [31:0] d,input [31:0] len);
        begin wr(8,s);wr(12,d);wr(16,len);wr(0,1);end
    endtask
    task wait_done;
        begin st=0;t=0;while(!st[1] && t<30000)begin rd(4,st);t=t+1;end
        if(!st[1])$fatal(1,"DMA never completed");end
    endtask
    task expect_config_error(input [31:0] s,input [31:0] d,input [31:0] len);
        begin launch(s,d,len);wait_done();if(!st[2]||st[5:3]!=1)$fatal(1,"bad config accepted");end
    endtask
    initial begin
        if($value$plusargs("SEED=%d",seed))begin end
        if($value$plusargs("N=%d",iterations))begin end
        rng=$urandom(seed);
        if($test$plusargs("TRACE"))begin $dumpfile("results/dma.vcd");$dumpvars(0,tb_dma);end
        for(j=0;j<1024;j=j+1)mem[j]=0;
        repeat(4)@(negedge clk);rst_n=1;wr(24,1);wr(28,1000);
        // CPU stays active on an unrelated memory location; both masters must progress.
        c_valid=1;c_addr=32'hf00;
        for(k=0;k<iterations;k=k+1) begin
            n=$urandom_range(1,128);
            for(j=0;j<128;j=j+1)begin mem[j]=$urandom;mem[256+j]=32'hdeadbeef;end
            launch(0,1024,n);wait_done();if(st[2])$fatal(1,"copy status %h",st);
            for(j=0;j<n;j=j+1)if(mem[j]!==mem[256+j])$fatal(1,"copy mismatch index=%d",j);
            if(n<128 && mem[256+n]!==32'hdeadbeef)$fatal(1,"wrote beyond end");
            rd(20,st);if(st!=n)$fatal(1,"completed count");
            if(!irq)$fatal(1,"IRQ missing");wr(4,2);if(irq)$fatal(1,"IRQ clear");
        end
        if(cpu_count<iterations)$fatal(1,"CPU starved");c_valid=0;
        launch(0,1024,0);wait_done();if(st[2])$fatal(1,"zero length");
        expect_config_error(1,1024,4);expect_config_error(0,1025,4);
        expect_config_error(0,4,4);expect_config_error(4,0,4);
        expect_config_error(0,0,1);expect_config_error(32'hfffffffc,1024,2);
        expect_config_error(0,32'hfffffffc,2);expect_config_error(0,1024,32'h40000000);
        // Read error must stop before writes. Write error counts only committed words.
        inject_error=1;error_addr=0;launch(0,1024,4);wait_done();
        if(st[5:3]!=2)$fatal(1,"read bus error");rd(20,st);if(st!=0)$fatal(1,"read error count");
        error_addr=1028;launch(0,1024,4);wait_done();
        if(st[5:3]!=2)$fatal(1,"write bus error");rd(20,st);if(st!=1)$fatal(1,"partial count");inject_error=0;
        // Timeout cancels the custom bus request. Arbiter must release the cancelled owner.
        freeze=1;wr(28,10);launch(0,1024,4);wait_done();
        if(st[5:3]!=3 || d_valid)$fatal(1,"timeout cancellation");freeze=0;
        wr(28,1000);launch(0,1024,4);wait_done();if(st[2])$fatal(1,"timeout recovery");
        // Busy writes ignored; asynchronous reset midway; then a fresh transfer.
        freeze=1;launch(0,1024,8);wr(8,512);wr(0,1);rd(8,st);
        if(st!=0)$fatal(1,"busy config accepted");
        #3;rst_n=0;#1;if(d_valid||irq)$fatal(1,"async reset");
        repeat(4)@(negedge clk);rst_n=1;freeze=0;launch(0,1024,7);wait_done();
        if(st[2])$fatal(1,"reset recovery");
        for(j=0;j<7;j=j+1)if(mem[j]!==mem[256+j])$fatal(1,"recovery copy");
        $display("PASS DMA: %0d randomized copies, %0d shared-bus beats, %0d CPU completions + fault/reset tests",iterations,beats,cpu_count);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"global watchdog");end
endmodule
