// ==========================
// ram_dp.v  (Verilog-2001)
// Dual-port RAM (write-first) + synthesizable zero-clear
// ==========================
`timescale 1ns/1ps
module ram_dp #(
    parameter WIDTH  = 16,
    parameter DEPTH  = 16,
    parameter ADDR_W = 4     // ceil(log2(DEPTH))
)(
    input                   clk,
    input                   rst_n,        // async assert, sync deassert OK for ctrl regs

    // ---- Port A ----
    input                   a_we,
    input  [ADDR_W-1:0]     a_addr,
    input  [WIDTH-1:0]      a_din,
    output reg [WIDTH-1:0]  a_dout,

    // ---- Port B ----
    input                   b_we,
    input  [ADDR_W-1:0]     b_addr,
    input  [WIDTH-1:0]      b_din,
    output reg [WIDTH-1:0]  b_dout,

    // ---- Clear control ----
    input                   clear_start,  // pulse/high to start bulk zero
    output reg              clear_busy,   // 1 while clearing
    output reg              clear_done    // 1 for one clk when finished
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Clear engine
    reg [ADDR_W-1:0] clear_addr;

    // Effective signals (user vs. clear overrides)
    reg               a_we_eff;
    reg [ADDR_W-1:0]  a_addr_eff;
    reg [WIDTH-1:0]   a_din_eff;

    reg               b_we_eff;
    reg [ADDR_W-1:0]  b_addr_eff;
    reg [WIDTH-1:0]   b_din_eff;

    // ---- Clear FSM ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_busy <= 1'b0;
            clear_done <= 1'b0;
            clear_addr <= {ADDR_W{1'b0}};
        end else begin
            clear_done <= 1'b0; // default
            if (!clear_busy) begin
                if (clear_start) begin
                    clear_busy <= 1'b1;
                    clear_addr <= {ADDR_W{1'b0}};
                end
            end else begin
                // advance clear address
                if (clear_addr == (DEPTH-1)) begin
                    clear_busy <= 1'b0;
                    clear_done <= 1'b1; // one-cycle pulse
                end
                clear_addr <= clear_addr + {{(ADDR_W-1){1'b0}},1'b1};
            end
        end
    end

    // ---- Port arbitration during clear ----
    // While clearing:
    //   - Port A is used to write zeros at clear_addr
    //   - Port B writes are disabled; reads allowed (observe progress)
    always @* begin
        if (clear_busy) begin
            a_we_eff   = 1'b1;
            a_addr_eff = clear_addr;
            a_din_eff  = {WIDTH{1'b0}};

            b_we_eff   = 1'b0;
            b_addr_eff = b_addr;
            b_din_eff  = b_din;
        end else begin
            a_we_eff   = a_we;
            a_addr_eff = a_addr;
            a_din_eff  = a_din;

            b_we_eff   = b_we;
            b_addr_eff = b_addr;
            b_din_eff  = b_din;
        end
    end

    // ---- Port A: synchronous R/W, write-first ----
    always @(posedge clk) begin
        if (a_we_eff) mem[a_addr_eff] <= a_din_eff;
        a_dout <= a_we_eff ? a_din_eff : mem[a_addr_eff];
    end

    // ---- Port B: synchronous R/W, write-first ----
    always @(posedge clk) begin
        if (b_we_eff) mem[b_addr_eff] <= b_din_eff;
        b_dout <= b_we_eff ? b_din_eff : mem[b_addr_eff];
    end

    // NOTE:
    // - Same-address, same-cycle writes on both ports are undefined; avoid upstream.
    // - Memory contents are not reset by rst_n; use clear_start/clear_busy to zero at runtime.
endmodule

