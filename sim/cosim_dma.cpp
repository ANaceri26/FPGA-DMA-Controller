#include "Vdma_controller.h"
#include "verilated.h"
#include "controllers.h"
#include <cstdio>
#include <cstdlib>
#include <random>
static Vdma_controller top;
static uint32_t memory[1024];static std::mt19937 rng(17);static bool freeze=false,bus_error=false;
static void check(bool ok,const char *s) { if(!ok) {std::fprintf(stderr,"FAIL: %s\n",s);std::exit(1);} }
static void tick() {
    top.clk=0;top.m_ready=!freeze && (rng()%4!=0);top.eval();
    bool range=top.m_addr<4096;top.m_rdata=range?memory[top.m_addr/4]:0;
    top.m_error=bus_error || !range;top.eval();
    if(top.rst_n && top.m_valid && top.m_ready && top.m_write && !top.m_error) memory[top.m_addr/4]=top.m_wdata;
    top.clk=1;top.eval();top.clk=0;top.eval();
}
static uint32_t read_reg(void *,uint32_t a) {top.reg_addr=a;top.reg_write=0;top.reg_valid=1;tick();return top.reg_rdata;}
static void write_reg(void *,uint32_t a,uint32_t v) {
    top.reg_addr=a;top.reg_wdata=v;top.reg_write=1;top.reg_valid=1;tick();top.reg_write=0;top.reg_valid=0;tick();
}
int main(int argc,char **argv) {
    Verilated::commandArgs(argc,argv);top.rst_n=0;tick();top.rst_n=1;tick();
    hw_io io={nullptr,read_reg,write_reg};uint32_t count=0;
    write_reg(nullptr,DMA_IRQ_ENABLE,1);
    for(int t=0;t<500;t++) {
        uint32_t n=1+rng()%128;
        for(unsigned i=0;i<128;i++){memory[i]=rng();memory[256+i]=0xdeadbeef;}
        check(dma_start(io,0,1024,n)==HW_OK,"start");
        check(dma_wait(io,10000,&count)==HW_OK && count==n,"completion count");
        for(unsigned i=0;i<n;i++)check(memory[i]==memory[256+i],"copy data");
        check(top.irq,"IRQ");write_reg(nullptr,DMA_STATUS,2);check(!top.irq,"IRQ clear");
    }
    check(dma_start(io,0,4,8)==HW_CONFIG_ERROR,"overlap");
    check(dma_start(io,1,1024,8)==HW_CONFIG_ERROR,"alignment");
    check(dma_start(io,0xfffffffc,1024,2)==HW_CONFIG_ERROR,"overflow");
    check(dma_start(io,0,1024,0)==HW_OK && dma_wait(io,10,&count)==HW_OK && count==0,"zero length");
    freeze=true;write_reg(nullptr,DMA_TIMEOUT,30);check(dma_start(io,0,1024,4)==HW_OK,"timeout start");
    check(dma_start(io,0,1024,4)==HW_BUSY,"busy");
    check(dma_wait(io,100,&count)==HW_TIMEOUT,"hardware timeout");freeze=false;
    bus_error=true;check(dma_start(io,0,1024,4)==HW_OK,"error start");
    check(dma_wait(io,100,&count)==HW_BUS_ERROR,"bus error");bus_error=false;
    freeze=true;check(dma_start(io,0,1024,4)==HW_OK,"poll start");
    check(dma_wait(io,1,&count)==HW_POLL_TIMEOUT,"poll timeout");freeze=false;
    check(dma_wait(io,100,&count)==HW_OK,"resume wait");
    std::puts("PASS C/RTL DMA: 500 randomized copies, IRQ, validation, busy, bus error, timeouts, recovery");
    top.final();return 0;
}
