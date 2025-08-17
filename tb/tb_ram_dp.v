`timescale 1ns/1ps

module tb_ram_dp;

  // ---- Parameters ----
  // Set these to match your DUT parameters
  parameter WIDTH  = 16;
  parameter DEPTH  = 32;
  parameter ADDR_W = 5;   // ceil(log2(DEPTH)) = 5 for DEPTH=32

  // ---- DUT I/O ----
  reg                   clk;
  reg                   rst_n;

  // Port A
  reg                   a_we;
  reg  [ADDR_W-1:0]     a_addr;
  reg  [WIDTH-1:0]      a_din;
  wire [WIDTH-1:0]      a_dout;

  // Port B
  reg                   b_we;
  reg  [ADDR_W-1:0]     b_addr;
  reg  [WIDTH-1:0]      b_din;
  wire [WIDTH-1:0]      b_dout;

  // Clear control
  reg                   clear_start;
  wire                  clear_busy;
  wire                  clear_done;

  // ---- Instantiate DUT ----
  ram_dp #(
    .WIDTH (WIDTH),
    .DEPTH (DEPTH),
    .ADDR_W(ADDR_W)
  ) dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .a_we        (a_we),
    .a_addr      (a_addr),
    .a_din       (a_din),
    .a_dout      (a_dout),
    .b_we        (b_we),
    .b_addr      (b_addr),
    .b_din       (b_din),
    .b_dout      (b_dout),
    .clear_start (clear_start),
    .clear_busy  (clear_busy),
    .clear_done  (clear_done)
  );

  // ---- Clock ----
  initial clk = 1'b0;
  always #5 clk = ~clk; // 100 MHz

  // ---- VCD ----
  initial begin
    $dumpfile("tb_ram_dp.vcd");
    $dumpvars(0, tb_ram_dp);
  end

  // ---- Error counter ----
  integer errors;

  // ---- Helpers ----
  task drive_idle;
  begin
    a_we = 0; a_addr = {ADDR_W{1'b0}}; a_din = {WIDTH{1'b0}};
    b_we = 0; b_addr = {ADDR_W{1'b0}}; b_din = {WIDTH{1'b0}};
    clear_start = 0;
  end
  endtask

  task wr_rd_A;
    input [ADDR_W-1:0] addr;
    input [WIDTH-1:0]  val;
  begin
    @(negedge clk);
    a_addr <= addr; a_din <= val; a_we <= 1'b1;
    @(negedge clk);
    a_we <= 1'b0;
    @(negedge clk);
    a_addr <= addr;
    @(negedge clk);
    if (a_dout !== val) begin
      $display("FAIL @%0t: A readback mismatch addr=%0d got=0x%0h exp=0x%0h",
               $time, addr, a_dout, val);
      errors = errors + 1;
    end else begin
      $display("PASS @%0t: A readback OK addr=%0d val=0x%0h",
               $time, addr, val);
    end
  end
  endtask

  task wr_rd_B;
    input [ADDR_W-1:0] addr;
    input [WIDTH-1:0]  val;
  begin
    @(negedge clk);
    b_addr <= addr; b_din <= val; b_we <= 1'b1;
    @(negedge clk);
    b_we <= 1'b0;
    @(negedge clk);
    b_addr <= addr;
    @(negedge clk);
    if (b_dout !== val) begin
      $display("FAIL @%0t: B readback mismatch addr=%0d got=0x%0h exp=0x%0h",
               $time, addr, b_dout, val);
      errors = errors + 1;
    end else begin
      $display("PASS @%0t: B readback OK addr=%0d val=0x%0h",
               $time, addr, val);
    end
  end
  endtask

  task parallel_write_then_read;
    input [ADDR_W-1:0] addrA; input [WIDTH-1:0] valA;
    input [ADDR_W-1:0] addrB; input [WIDTH-1:0] valB;
  begin
    @(negedge clk);
    a_addr <= addrA; a_din <= valA; a_we <= 1'b1;
    b_addr <= addrB; b_din <= valB; b_we <= 1'b1;
    @(negedge clk);
    a_we <= 1'b0; b_we <= 1'b0;
    @(negedge clk);
    a_addr <= addrA; b_addr <= addrB;
    @(negedge clk);
    if (a_dout !== valA) begin
      $display("FAIL @%0t: Parallel A readback mismatch addr=%0d got=0x%0h exp=0x%0h",
               $time, addrA, a_dout, valA);
      errors = errors + 1;
    end else begin
      $display("PASS @%0t: Parallel A readback OK addr=%0d",
               $time, addrA);
    end
    if (b_dout !== valB) begin
      $display("FAIL @%0t: Parallel B readback mismatch addr=%0d got=0x%0h exp=0x%0h",
               $time, addrB, b_dout, valB);
      errors = errors + 1;
    end else begin
      $display("PASS @%0t: Parallel B readback OK addr=%0d",
               $time, addrB);
    end
  end
  endtask

  task write_first_same_port_A;
    input [ADDR_W-1:0] addr;
    input [WIDTH-1:0]  val;
  begin
    @(negedge clk);
    a_addr <= addr; a_din <= val; a_we <= 1'b1;
    @(negedge clk); // a_dout should reflect val at this posedge (write-first)
    a_we <= 1'b0;
    @(negedge clk);
    a_addr <= addr;
    @(negedge clk);
    if (a_dout !== val) begin
      $display("FAIL @%0t: A write-first failed addr=%0d got=0x%0h exp=0x%0h",
               $time, addr, a_dout, val);
      errors = errors + 1;
    end else begin
      $display("PASS @%0t: A write-first OK addr=%0d",
               $time, addr);
    end
  end
  endtask

  // A writes new value while B reads same address in same cycle:
  // expect B to observe OLD value (read-old across ports)
  task crossport_same_cycle_write_read_old;
    input [ADDR_W-1:0] addr;
    input [WIDTH-1:0]  oldv;
    input [WIDTH-1:0]  newv;
  begin
    // preset old value via A
    wr_rd_A(addr, oldv);

    // same cycle: A write, B read
    @(negedge clk);
    a_addr <= addr; a_din <= newv; a_we <= 1'b1;
    b_addr <= addr; b_we <= 1'b0;
    @(negedge clk);
    a_we <= 1'b0;

    if (b_dout !== oldv) begin
      $display("FAIL @%0t: Cross-port read-old failed addr=%0d got=0x%0h exp(old)=0x%0h",
               $time, addr, b_dout, oldv);
      errors = errors + 1;
    end else begin
      $display("PASS @%0t: Cross-port read-old OK addr=%0d",
               $time, addr);
    end

    // confirm new value is stored
    @(negedge clk);
    b_addr <= addr;
    @(negedge clk);
    if (b_dout !== newv) begin
      $display("FAIL @%0t: Cross-port post-write readback mismatch addr=%0d got=0x%0h exp=0x%0h",
               $time, addr, b_dout, newv);
      errors = errors + 1;
    end else begin
      $display("PASS @%0t: Cross-port post-write readback OK addr=%0d",
               $time, addr);
    end
  end
  endtask

  task do_clear_and_verify;
    integer k;
  begin
    @(negedge clk);
    clear_start <= 1'b1;
    @(negedge clk);
    clear_start <= 1'b0;

    // wait for busy and done
    wait (clear_busy == 1'b1);
    $display("INFO @%0t: clear_busy asserted", $time);
    wait (clear_done == 1'b1);
    $display("INFO @%0t: clear_done pulse seen", $time);
    @(negedge clk);
    if (clear_busy !== 1'b0) begin
      $display("FAIL @%0t: clear_busy did not deassert after done", $time);
      errors = errors + 1;
    end

    // verify all zeros
    for (k = 0; k < DEPTH; k = k + 1) begin
      @(negedge clk);
      a_addr <= k[ADDR_W-1:0];
      b_addr <= k[ADDR_W-1:0];
      @(negedge clk);
      if (a_dout !== {WIDTH{1'b0}}) begin
        $display("FAIL @%0t: After clear A addr=%0d not zero: 0x%0h",
                 $time, k, a_dout);
        errors = errors + 1;
      end
      if (b_dout !== {WIDTH{1'b0}}) begin
        $display("FAIL @%0t: After clear B addr=%0d not zero: 0x%0h",
                 $time, k, b_dout);
        errors = errors + 1;
      end
    end
    $display("PASS @%0t: Full zero verify after clear", $time);
  end
  endtask

  task random_stress;
    input integer ops;
    integer n;
    reg [ADDR_W-1:0] ra, rb;
    reg [WIDTH-1:0]  va, vb;
  begin
    for (n = 0; n < ops; n = n + 1) begin
      ra = $random % DEPTH; va = $random;
      rb = $random % DEPTH; vb = $random;
      if (rb == ra) rb = (rb + 1) % DEPTH; // avoid undefined dual write same addr

      @(negedge clk);
      a_addr <= ra; a_din <= va; a_we <= 1'b1;
      b_addr <= rb; b_din <= vb; b_we <= 1'b1;
      @(negedge clk);
      a_we <= 1'b0; b_we <= 1'b0;

      @(negedge clk);
      a_addr <= ra; b_addr <= rb;
      @(negedge clk);
      if (a_dout !== va) begin
        $display("FAIL @%0t: rand A readback mismatch addr=%0d got=0x%0h exp=0x%0h",
                 $time, ra, a_dout, va);
        errors = errors + 1;
      end
      if (b_dout !== vb) begin
        $display("FAIL @%0t: rand B readback mismatch addr=%0d got=0x%0h exp=0x%0h",
                 $time, rb, b_dout, vb);
        errors = errors + 1;
      end
    end
    $display("PASS @%0t: Random stress OK", $time);
  end
  endtask

  // ---- Main sequence ----
  initial begin
    errors = 0;
    drive_idle();

    // Reset
    rst_n = 0;
    repeat (2) @(negedge clk);
    rst_n = 1;

    // 1) Basic single-port ops
    wr_rd_A(5, 16'h1111);
    wr_rd_B(9, 16'hABCD);

    // 2) Parallel ops different addresses
    parallel_write_then_read(3, 16'h1234, 7, 16'hBEEF);

    // 3) Same-port write-first (A)
    write_first_same_port_A(12, 16'hCAFE);

    // 4) Cross-port same-cycle write/read (expect read-old on B)
    crossport_same_cycle_write_read_old(14, 16'h00AA, 16'h55FF);

    // 5) Clear and verify all zeros
    do_clear_and_verify();

    // 6) Mid-clear probe demo (optional): reseed a couple of words then clear again
    wr_rd_A(2, 16'h0F0F);
    wr_rd_B(4, 16'hF0F0);
    do_clear_and_verify();

    // 7) Random stress
    random_stress(50);

    // Summary
    if (errors == 0) $display("==== ALL TESTS PASSED ====");
    else             $display("==== TESTS FAILED: %0d error(s) ====", errors);

    $finish;
  end

endmodule

