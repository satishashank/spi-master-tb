class transaction;
    randc bit [7:0] data;

    function transaction copy();
        copy = new();
        copy.data = this.data;
    endfunction
    function void display();
        $strobe("DATA: %0h", data);
    endfunction
endclass

class spi_coverage;
    transaction tx;
    bit [1:0] mode;  // set once from TB parameter, never changes

    covergroup mosi_cg;
        cp_mosi: coverpoint tx.data {
            bins zero     = {8'h00};
            bins all_ones = {8'hFF};
            bins alt_10   = {8'hAA};
            bins alt_01   = {8'h55};
            bins msb_only = {8'h80};
            bins lsb_only = {8'h01};
            bins rest     = {[8'h02:8'hFE]};
        }
    endgroup

    covergroup miso_cg;
        cp_miso: coverpoint tx.data {
            bins zero     = {8'h00};
            bins all_ones = {8'hFF};
            bins alt_10   = {8'hAA};
            bins alt_01   = {8'h55};
            bins msb_only = {8'h80};
            bins lsb_only = {8'h01};
            bins rest     = {[8'h02:8'hFE]};
        }
    endgroup

    // mode sampled once at the start — not per transaction
    covergroup mode_cg;
        cp_mode: coverpoint mode {
            bins mode0 = {2'b00};
            bins mode1 = {2'b01};
            bins mode2 = {2'b10};
            bins mode3 = {2'b11};
        }
    endgroup

    function new(bit [1:0] tb_mode);
        mosi_cg = new();
        miso_cg = new();
        mode_cg = new();
        this.mode = tb_mode;
        mode_cg.sample();   // sample once right here — mode never changes
    endfunction

    // called by slave-side monitor after 8 MOSI bits received
    function void sample_mosi(transaction t);
        this.tx = t;
        mosi_cg.sample();
    endfunction

    // called by master-side monitor after o_RX_DV pulses
    function void sample_miso(transaction t);
        this.tx = t;
        miso_cg.sample();
    endfunction

    function void report();
        $display("=== Coverage Report ===");
        $display("MOSI  : %0.2f%%", mosi_cg.get_coverage());
        $display("MISO  : %0.2f%%", miso_cg.get_coverage());
        $display("Mode  : %0.2f%%", mode_cg.get_coverage());
    endfunction
endclass

class scoreboard;
    int n;
    transaction tx_mon,rx_mon,tx_gen,rx_gen;
    mailbox #(transaction) mbx_tx_mon;
    mailbox #(transaction) mbx_rx_mon;
    mailbox #(transaction) mbx_tx_gen;
    mailbox #(transaction) mbx_rx_gen;
    spi_coverage cov;
    function new(int n, mailbox #(transaction) mbx_tx_mon, mailbox #(transaction) mbx_rx_mon, mailbox #(transaction) mbx_tx_gen, mailbox #(transaction) mbx_rx_gen,spi_coverage cov);
        this.n = n;
        this.mbx_tx_mon = mbx_tx_mon;
        this.mbx_rx_mon = mbx_rx_mon;
        this.mbx_tx_gen = mbx_tx_gen;
        this.mbx_rx_gen = mbx_rx_gen;
        this.cov = cov;
    endfunction

    task run();
        int i,j,x,y;
        x = 0;
        y = 0;
        fork
        for(i = 0; i<n; i++) begin
            mbx_tx_gen.get(tx_gen);
            mbx_tx_mon.get(tx_mon);
            assert(tx_mon.data == tx_gen.data) else begin
                 $error("[SCOREBOARD] TX data mismatch: Monitored: %0h, Generated: %0h", tx_mon.data, tx_gen.data);
                 x = x+1;
                  end
            $display("[SCOREBOARD] Tx matched %0d, data: %0h", i+1, tx_mon.data);
        end
        for(j = 0; j<n; j++) begin
            mbx_rx_mon.get(rx_mon);
            mbx_rx_gen.get(rx_gen);
            assert(rx_mon.data == rx_gen.data) else begin
                 $error("[SCOREBOARD] RX data mismatch: Monitored: %0h, Generated: %0h", rx_mon.data, rx_gen.data);
                 y = y+1;
            end
            $display("[SCOREBOARD] Rx matched %0d, data: %0h", j+1, rx_mon.data);
        end
        join
        cov.report();
        $display("[SCOREBOARD] === All %0d transactions complete %0d TX mismatches, %0d RX mismatches ===", n, x, y);
        $finish;
    endtask
endclass



class generator;
    mailbox #(transaction) mbx_tx_sb;
    mailbox #(transaction) mbx_tx_drv;
    mailbox #(transaction) mbx_rx_drv;
    mailbox #(transaction) mbx_rx_sb;
    int n;
    transaction tx,rx;

  function new(int n,mailbox #(transaction) mbx_tx_sb, mailbox #(transaction) mbx_rx_sb, mailbox #(transaction) mbx_tx_drv, mailbox #(transaction) mbx_rx_drv);
    this.mbx_tx_sb = mbx_tx_sb;
    this.mbx_rx_sb = mbx_rx_sb;
    this.mbx_tx_drv = mbx_tx_drv;
    this.mbx_rx_drv = mbx_rx_drv;
    this.n = n;
    this.tx = new();
    this.rx = new();
    endfunction
  
  task run();
    int i;
    for(i = 0; i<n; i++) begin
      assert(tx.randomize()) else $display("Randomization Failed TX");
      assert(rx.randomize()) else $display("Randomization Failed RX");
      $strobe("[GEN] : DATA SENT TO DRIVER TX");
      $strobe("[GEN] : DATA SENT TO DRIVER RX");
      tx.display();
      rx.display();
      mbx_tx_sb.put(tx.copy);
      mbx_rx_sb.put(rx.copy);
      mbx_tx_drv.put(tx.copy);
      mbx_rx_drv.put(rx.copy);
    end
  endtask

  endclass
class monitor;
    virtual spi_if vif;
    transaction rx;
    transaction tx;
    spi_coverage cov;
    bit [1:0] spi_mode;
    mailbox #(transaction) mbx_rx_sb;
    mailbox #(transaction) mbx_tx_sb;
    function new(virtual spi_if vif, mailbox #(transaction) mbx_rx_sb, mailbox #(transaction) mbx_tx_sb, bit [1:0] spi_mode = 2'b00);
        this.vif = vif;
        this.mbx_rx_sb = mbx_rx_sb;
        this.mbx_tx_sb = mbx_tx_sb;
        this.spi_mode = spi_mode;
        this.cov = new(spi_mode);
    endfunction

    task rcv_data_master();
    forever begin
        rx = new();
        @(posedge vif.i_Clk iff vif.o_RX_DV);
        rx.data = vif.o_RX_Byte;
      	$strobe("[MON:Master] Received data from slave: %0h", rx.data);
        mbx_rx_sb.put(rx);
        cov.sample_miso(rx);

    end
    endtask

    task rcv_data_slave();
    forever begin
        int i;
        tx = new();

        @(negedge vif.o_TX_Ready);
        for(i = 0; i < 8; i++) begin
            if(spi_mode[1]^spi_mode[0] == 0)
            @(posedge vif.o_SPI_Clk);
            else
            @(negedge vif.o_SPI_Clk);
            tx.data[7-i] = vif.o_SPI_MOSI;
        end
      $strobe("[MON:Slave] Received data from master: %0h", tx.data);
        mbx_tx_sb.put(tx);
        cov.sample_mosi(tx);
    end
    endtask

    task run();
            fork
            rcv_data_master();
            rcv_data_slave();
            join_none
    endtask
endclass


    
class driver_master;
    virtual spi_if vif;
    mailbox #(transaction) mbx_tx;
    transaction tx;

    function new(virtual spi_if vif, mailbox #(transaction) mbx_tx);
        this.vif = vif;
        this.mbx_tx = mbx_tx;
    endfunction

    task drive_data_master();
        mbx_tx.get(tx);
        @(posedge vif.i_Clk iff vif.o_TX_Ready);
        vif.i_TX_DV <= 1;
        vif.i_TX_Byte <= tx.data;
        @(posedge vif.i_Clk);
        vif.i_TX_DV <= 0;
        $strobe("[DRV:Master] DATA added to MASTER: %0h with DV: %0b", tx.data, vif.i_TX_DV);
    endtask

    task run();
        forever begin
            drive_data_master();
        end
    endtask
endclass

class driver_slave;
    virtual spi_if vif;
    mailbox #(transaction) mbx_rx;
    transaction rx;
    bit [1:0] spi_mode;
    function new(virtual spi_if vif, mailbox #(transaction) mbx_rx, bit [1:0] spi_mode = 2'b00);
        this.vif = vif;
        this.mbx_rx = mbx_rx;
        this.spi_mode = spi_mode;
    endfunction

    task drive_data_slave();
        int i;
        mbx_rx.get(rx);
        @(negedge vif.o_TX_Ready);
        if(spi_mode[0] == 0) begin
            vif.i_SPI_MISO<= rx.data[7];

            for(i = 1; i < 8; i++) begin
                if(spi_mode[1] == 0) begin
                    @(negedge vif.o_SPI_Clk);
                end
                else begin
                    @(posedge vif.o_SPI_Clk);
                end
                vif.i_SPI_MISO <= rx.data[7-i];
            end
        end
        else begin
            for(i = 0; i < 8; i++) begin
                if(spi_mode[1] == 0) begin
                    @(posedge vif.o_SPI_Clk);
                end
                else begin
                    @(negedge vif.o_SPI_Clk);
                end
                vif.i_SPI_MISO <= rx.data[7-i];
            end
        end
        $strobe("[DRV:Slave] DATA sent to master: %0h", rx.data);
    endtask
    task run();
        forever begin
            drive_data_slave();
        end
    endtask

    



endclass
interface spi_if;
    logic i_Clk;       // FPGA Clock
    logic i_Rst_L;     // FPGA Reset
    logic [7:0] i_TX_Byte;
    logic i_TX_DV;
    logic o_TX_Ready;
    logic o_RX_DV;
    logic [7:0] o_RX_Byte;
    logic o_SPI_Clk;
    logic i_SPI_MISO;
    logic o_SPI_MOSI;
endinterface

module TB;
    parameter bit[1:0] spi_mode = 2'b10; // Default SPI mode
    spi_if tb_if();       //Central interface
    driver_master tb_driver_master;
    driver_slave tb_driver_slave;
    monitor tb_monitor;
    generator tb_gen;
    scoreboard tb_sb;
    mailbox #(transaction) mbx_tx_gen2drv;
    mailbox #(transaction) mbx_rx_gen2drv;
    mailbox #(transaction) mbx_tx_gen2sb;
    mailbox #(transaction) mbx_rx_gen2sb;
    mailbox #(transaction) mbx_tx_mon2sb;
    mailbox #(transaction) mbx_rx_mon2sb;

    spi_master #(.SPI_MODE(spi_mode)) dut (
    .i_Rst_L(tb_if.i_Rst_L),
    .i_Clk(tb_if.i_Clk),
    .i_TX_Byte(tb_if.i_TX_Byte),
    .i_TX_DV(tb_if.i_TX_DV),
    .o_TX_Ready(tb_if.o_TX_Ready),
    .o_RX_DV(tb_if.o_RX_DV),
    .o_RX_Byte(tb_if.o_RX_Byte),
    .o_SPI_Clk(tb_if.o_SPI_Clk),
    .i_SPI_MISO(tb_if.i_SPI_MISO),
    .o_SPI_MOSI(tb_if.o_SPI_MOSI)
);
initial begin
    tb_if.i_Clk = 0;
    forever #5 tb_if.i_Clk = ~tb_if.i_Clk;
end

initial begin
    int number = 10; // Number of transactions to generate
    //mailboxes
    mbx_tx_gen2drv = new();
    mbx_rx_gen2drv = new();
    mbx_tx_gen2sb = new();
    mbx_rx_gen2sb = new();
    mbx_tx_mon2sb = new();
    mbx_rx_mon2sb = new();

    // Instantiate the driver, monitor, generator, and scoreboard
  	tb_driver_master = new(tb_if, mbx_tx_gen2drv);
    tb_driver_slave = new(tb_if, mbx_rx_gen2drv,spi_mode);
    tb_monitor = new(tb_if, mbx_rx_mon2sb, mbx_tx_mon2sb,spi_mode);
    tb_gen = new(number, mbx_tx_gen2drv, mbx_rx_gen2drv, mbx_tx_gen2sb, mbx_rx_gen2sb);  // Generate number transactions
    tb_sb = new(number, mbx_tx_mon2sb, mbx_rx_mon2sb,mbx_tx_gen2sb, mbx_rx_gen2sb,tb_monitor.cov);
    tb_if.i_Rst_L = 0;
    #20;
    tb_if.i_Rst_L = 1;
        fork
          tb_driver_master.run();
          tb_driver_slave.run();
          tb_monitor.run();
          tb_gen.run();
          tb_sb.run();
        join
    end

initial begin
    $timeout(2000);
    $dumpfile("spi_master.vcd");
    $dumpvars(0, TB);
 end

endmodule